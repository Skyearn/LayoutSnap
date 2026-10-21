import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// 真正干活的：把布局里的窗口一个个搬回去
final class WindowRestorer {

    struct Options {
        /// 应用没开就自动打开
        var launchMissingApps = true
        /// 等待应用把窗口交出来的最长时间
        var appLaunchTimeout: TimeInterval = 15
        /// 恢复窗口叠放顺序（会调用 AXRaise）
        var restoreStackingOrder = true
        /// 兼容模式：针对 Electron / Chromium 系应用（VS Code、Chrome 等）
        /// 临时关掉 AXEnhancedUserInterface，否则它们会忽略移动窗口的请求
        var compatibilityMode = true
        /// 保存时是全屏的窗口，恢复时也切回全屏（默认关，容易吓人）
        var restoreFullScreenWindows = false
        /// 同时处理几个应用。同一个应用内部始终串行。
        var maxConcurrentApps = 4

        static var `default`: Options { Options() }
    }

    private let queue = DispatchQueue(label: "com.layoutsnap.restore", qos: .userInitiated)

    /// 上一次恢复后遗留的窗口，用于「撤销恢复」这类操作（暂时没用上，留个钩子）
    private(set) var lastAllocated: [AXUIElement] = []

    // MARK: - 入口

    func restore(layout: Layout,
                 options: Options = .default,
                 progress: @escaping (String) -> Void,
                 completion: @escaping (RestoreReport) -> Void) {
        let snapshots = layout.enabledWindows
        let disabledCount = layout.windows.count - snapshots.count
        if disabledCount > 0 {
            Log.info("布局「\(layout.name)」里有 \(disabledCount) 个窗口被停用，本次跳过")
        }
        restore(snapshots: snapshots,
                name: layout.name,
                options: options,
                progress: progress,
                completion: completion)
    }

    /// 只恢复指定的若干窗口。用于「只把这一个窗口归位」。
    func restore(snapshots: [WindowSnapshot],
                 name: String,
                 options: Options = .default,
                 progress: @escaping (String) -> Void,
                 completion: @escaping (RestoreReport) -> Void) {

        let started = Date()
        Log.info("开始恢复「\(name)」，共 \(snapshots.count) 个窗口")

        queue.async { [weak self] in
            guard let self else { return }
            var report = RestoreReport()
            var restoredWindows: [(snapshot: WindowSnapshot, window: AXUIElement)] = []

            guard snapshots.isEmpty == false else {
                DispatchQueue.main.async { completion(report) }
                return
            }

            let groups = Dictionary(grouping: snapshots, by: { $0.bundleID })
                .map { (bundleID: $0.key, snapshots: $0.value) }
                .sorted { lhs, rhs in
                    (lhs.snapshots.map(\.zIndex).min() ?? 0) < (rhs.snapshots.map(\.zIndex).min() ?? 0)
                }

            // 不同应用之间互不干扰，可以并行搬；同一个应用内部仍然串行，
            // 免得应用自己的窗口管理逻辑互相打架。
            let resultLock = NSLock()
            let semaphore = DispatchSemaphore(value: max(1, options.maxConcurrentApps))
            let waitGroup = DispatchGroup()
            let workers = DispatchQueue(label: "com.layoutsnap.restore.app", attributes: .concurrent)

            for entry in groups {
                semaphore.wait()
                waitGroup.enter()
                workers.async {
                    defer {
                        semaphore.signal()
                        waitGroup.leave()
                    }
                    let outcome = self.restoreApp(bundleID: entry.bundleID,
                                                  snapshots: entry.snapshots,
                                                  options: options,
                                                  progress: progress)
                    resultLock.lock()
                    report.restored += outcome.report.restored
                    report.skipped += outcome.report.skipped
                    report.failed += outcome.report.failed
                    report.notes.append(contentsOf: outcome.report.notes)
                    restoredWindows.append(contentsOf: outcome.windows)
                    resultLock.unlock()
                }
            }
            waitGroup.wait()

            // 叠放顺序：从后往前 raise，最后抬的就在最前面
            if options.restoreStackingOrder {
                let ordered = restoredWindows.sorted { $0.snapshot.zIndex > $1.snapshot.zIndex }
                for item in ordered {
                    AX.limitMessagingTimeout(item.window, seconds: 0.5)
                    AX.perform(item.window, AXAction.raise)
                }
            }

            let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
            Log.info("恢复完成：\(report.summary)，耗时 \(elapsed)s")
            DispatchQueue.main.async { completion(report) }
        }
    }

    /// 处理一个应用的所有窗口（并行单元）
    private func restoreApp(bundleID: String,
                            snapshots: [WindowSnapshot],
                            options: Options,
                            progress: @escaping (String) -> Void
    ) -> (report: RestoreReport, windows: [(WindowSnapshot, AXUIElement)]) {
        var appReport = RestoreReport()
        var restored: [(WindowSnapshot, AXUIElement)] = []
        let appName = AppLauncher.appName(for: bundleID)
        let wasRunning = AppLauncher.isRunning(bundleID)
        self.report(progress, "正在处理 \(appName)…")

        guard let pid = resolvePID(bundleID: bundleID,
                                   options: options,
                                   wasRunning: wasRunning,
                                   progress: progress) else {
            // 应用没运行，且用户关掉了「恢复时启动未运行的应用」
            if wasRunning == false && options.launchMissingApps == false {
                appReport.skipped += snapshots.count
                appReport.notes.append("\(appName)：未运行，已跳过")
            } else {
                appReport.failed += snapshots.count
                appReport.notes.append("\(appName)：无法启动")
            }
            return (appReport, restored)
        }

        let appElement = AX.application(for: pid)
        AX.limitMessagingTimeout(appElement, seconds: 1.0)

        let windows = waitForWindows(appElement,
                                     expected: snapshots.count,
                                     timeout: wasRunning ? 2.0 : options.appLaunchTimeout)
        guard windows.isEmpty == false else {
            appReport.failed += snapshots.count
            appReport.notes.append("\(appName)：没有找到窗口")
            return (appReport, restored)
        }

        let candidates = WindowMatcher.match(snapshots: snapshots.sorted { $0.zIndex < $1.zIndex },
                                             to: windows)
        for candidate in candidates {
            guard let window = candidate.window else {
                appReport.failed += 1
                continue
            }
            switch apply(snapshot: candidate.snapshot, window: window, options: options, appName: appName) {
            case .restored:
                appReport.restored += 1
                restored.append((candidate.snapshot, window))
            case .skipped(let reason):
                appReport.skipped += 1
                if let reason { appReport.notes.append("\(appName)：\(reason)") }
            case .failed(let reason):
                appReport.failed += 1
                appReport.notes.append("\(appName)：\(reason)")
            }
        }
        return (appReport, restored)
    }

    // MARK: - 单个窗口

    private enum Outcome {
        case restored
        case skipped(String?)
        case failed(String)
    }

    private func apply(snapshot: WindowSnapshot,
                       window: AXUIElement,
                       options: Options,
                       appName: String) -> Outcome {

        AX.limitMessagingTimeout(window, seconds: 1.0)

        let isFullScreenNow = AX.bool(window, AXAttr.fullScreen) ?? false

        if snapshot.isFullScreen {
            if isFullScreenNow { return .skipped(nil) }
            if options.restoreFullScreenWindows {
                return AX.setBool(window, AXAttr.fullScreen, true) ? .restored : .failed("切换全屏失败")
            }
            return .skipped("保存时处于全屏")
        }

        // 现在全屏、当时不全屏：不碰它，免得把用户正在全屏用的窗口踢出来
        if isFullScreenNow { return .skipped("当前处于全屏") }

        // 最小化的先叫回来，否则改位置多半无效
        if AX.bool(window, AXAttr.minimized) == true {
            AX.setBool(window, AXAttr.minimized, false)
            // 等它真的回来再继续，一般十几毫秒，比固定睡 250ms 快得多
            waitUntil(timeout: 0.4) { AX.bool(window, AXAttr.minimized) == false }
        }

        guard snapshot.frame.isUsableWindowFrame else { return .skipped("窗口尺寸异常") }

        let target = ScreenGeometry.resolveTarget(for: snapshot)

        // 兼容模式
        var restoreEnhancedUI = false
        if options.compatibilityMode,
           AX.bool(window, AXAttr.enhancedUserInterface) == true {
            AX.setBool(window, AXAttr.enhancedUserInterface, false)
            restoreEnhancedUI = true
            usleep(60_000)
        }

        var success = moveAndResize(window: window, to: target.frame, raiseOnRetry: options.compatibilityMode)

        if !success && options.compatibilityMode {
            // 有些应用要先把窗口抬到最前才接受几何变更
            AX.perform(window, AXAction.raise)
            usleep(40_000)
            success = moveAndResize(window: window, to: target.frame, raiseOnRetry: false)
        }

        if restoreEnhancedUI {
            AX.setBool(window, AXAttr.enhancedUserInterface, true)
        }

        if success {
            if target.remapped {
                return .restored
            }
            return .restored
        }
        return .failed("移动窗口失败（应用可能不允许用脚本改窗口）")
    }

    /// 位置 + 尺寸一起设。顺序试两遍，因为不同应用脾气不一样。
    private func moveAndResize(window: AXUIElement, to target: CGRect, raiseOnRetry: Bool) -> Bool {
        let tolerance: CGFloat = 2.0

        for attempt in 0..<3 {
            if attempt == 1 && raiseOnRetry {
                AX.perform(window, AXAction.raise)
                usleep(40_000)
            }
            if attempt % 2 == 0 {
                AX.setFrameOrigin(window, target.origin)
                AX.setFrameSize(window, target.size)
            } else {
                AX.setFrameSize(window, target.size)
                AX.setFrameOrigin(window, target.origin)
            }
            AX.setFrameOrigin(window, target.origin)

            // 轮询而不是死等：大多数窗口十几毫秒就到位了
            let arrived = waitUntil(timeout: 0.15, interval: 0.01) {
                guard let current = AX.frame(of: window) else { return false }
                return self.match(current, target, tolerance: tolerance)
            }
            if arrived { return true }
        }

        // 尺寸被应用的最小/最大尺寸限制住时，位置对上也认了
        if let current = AX.frame(of: window) {
            return abs(current.origin.x - target.origin.x) <= tolerance
                && abs(current.origin.y - target.origin.y) <= tolerance
                && abs(current.width - target.width) <= 24
                && abs(current.height - target.height) <= 24
        }
        return false
    }

    private func match(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    // MARK: - 辅助

    private func resolvePID(bundleID: String,
                            options: Options,
                            wasRunning: Bool,
                            progress: @escaping (String) -> Void) -> pid_t? {
        if wasRunning { return AppLauncher.runningPID(bundleID) }
        guard options.launchMissingApps else { return nil }
        return AppLauncher.ensureRunning(bundleID: bundleID,
                                         timeout: options.appLaunchTimeout,
                                         progress: { message in self.report(progress, message) })
    }

    private func waitForWindows(_ appElement: AXUIElement,
                                expected: Int,
                                timeout: TimeInterval) -> [AXUIElement] {
        let deadline = Date().addingTimeInterval(max(1.0, timeout))
        var best: [AXUIElement] = []
        var idle = 0

        while Date() < deadline {
            let windows = AX.windows(ofApplication: appElement).filter { window in
                guard let role = AX.string(window, AXAttr.role), role == AXRole.window else { return false }
                return true
            }
            if windows.count > best.count { best = windows }
            if best.count >= expected { break }
            // 已经稳定一会儿就不要再等了
            if windows.count == best.count {
                idle += 1
                if idle > 12 && !best.isEmpty { break }
            } else {
                idle = 0
            }
            usleep(60_000)
        }
        return best
    }

    /// 等到条件成立或者超时。
    ///
    /// 比固定 sleep 快得多：应用通常十几毫秒就响应了，固定睡 90ms 是纯浪费；
    /// 万一某个应用慢，也能一直等到超时为止。
    @discardableResult
    private func waitUntil(timeout: TimeInterval,
                           interval: TimeInterval = 0.012,
                           _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if condition() { return true }
            if Date() >= deadline { return false }
            usleep(useconds_t(interval * 1_000_000))
        }
    }

    private func report(_ callback: @escaping (String) -> Void, _ message: String) {
        DispatchQueue.main.async { callback(message) }
    }
}
