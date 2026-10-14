import Foundation
import AppKit
import CoreGraphics

struct ScanOptions {
    var includeMinimized = true
    var includeDialogs = true
    var excludedBundleIDs: Set<String> = []
    /// 太小的窗口（浮窗、提示条）不记录
    var minimumWidth: CGFloat = 60
    var minimumHeight: CGFloat = 40
    /// 同时扫几个应用
    var maxConcurrentApps = 4
}

/// 扫描当前所有普通应用的窗口，生成快照
enum WindowScanner {

    // MARK: - 全部窗口

    static func snapshot(options: ScanOptions = ScanOptions()) -> [WindowSnapshot] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let apps: [(app: NSRunningApplication, bundleID: String)] =
            NSWorkspace.shared.runningApplications.compactMap { app in
                guard app.activationPolicy == .regular,
                      let bundleID = app.bundleIdentifier,
                      (app.processIdentifier == myPID) == false,
                      options.excludedBundleIDs.contains(bundleID) == false else { return nil }
                return (app, bundleID)
            }
        guard apps.isEmpty == false else { return [] }

        // 显示器列表只取一次：NSScreen 查询不便宜，窗口多的时候会被调用几百次
        let displays = ScreenGeometry.currentDisplays
        let zOrder = windowZOrder()

        let lock = NSLock()
        var collected: [WindowSnapshot] = []
        let semaphore = DispatchSemaphore(value: max(1, options.maxConcurrentApps))
        let group = DispatchGroup()
        let workers = DispatchQueue(label: "com.windowsnap.scan", attributes: .concurrent)

        for entry in apps {
            semaphore.wait()
            group.enter()
            workers.async {
                defer {
                    semaphore.signal()
                    group.leave()
                }
                let snapshots = scan(app: entry.app,
                                     bundleID: entry.bundleID,
                                     displays: displays,
                                     options: options)
                guard snapshots.isEmpty == false else { return }

                // z 序表是共享的，取号要加锁
                lock.lock()
                var numbered: [WindowSnapshot] = []
                for var snapshot in snapshots {
                    snapshot.zIndex = zOrder.value(pid: entry.app.processIdentifier,
                                                   rect: snapshot.frame.cgRect,
                                                   fallback: numbered.count)
                    numbered.append(snapshot)
                }
                collected.append(contentsOf: numbered)
                lock.unlock()
            }
        }

        group.wait()
        return collected.sorted { $0.zIndex < $1.zIndex }
    }

    /// 扫一个应用的所有窗口
    private static func scan(app: NSRunningApplication,
                             bundleID: String,
                             displays: [DisplayInfo],
                             options: ScanOptions) -> [WindowSnapshot] {
        let element = AX.application(for: app.processIdentifier)
        AX.limitMessagingTimeout(element, seconds: 1.0)

        let axWindows = AX.windows(ofApplication: element)
        guard axWindows.isEmpty == false else { return [] }

        var snapshots: [WindowSnapshot] = []
        for window in axWindows {
            AX.limitMessagingTimeout(window, seconds: 1.0)

            guard let role = AX.string(window, AXAttr.role), role == AXRole.window else { continue }
            let subrole = AX.string(window, AXAttr.subrole) ?? ""
            if subrole == AXRole.sheet { continue }
            if options.includeDialogs == false && subrole == AXRole.dialog { continue }

            guard let rect = AX.frame(of: window) else { continue }
            let minimized = AX.bool(window, AXAttr.minimized) ?? false
            if minimized && options.includeMinimized == false { continue }
            if minimized == false && (rect.width < options.minimumWidth || rect.height < options.minimumHeight) { continue }

            snapshots.append(makeSnapshot(window: window,
                                          app: app,
                                          bundleID: bundleID,
                                          role: role,
                                          subrole: subrole,
                                          rect: rect,
                                          minimized: minimized,
                                          displays: displays))
        }
        return snapshots
    }

    // MARK: - 单个窗口

    /// 只取「当前正在用的那个窗口」：最前面那个应用的焦点窗口
    static func snapshotFrontmostWindow(options: ScanOptions = ScanOptions()) -> WindowSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              (app.processIdentifier == ProcessInfo.processInfo.processIdentifier) == false,
              options.excludedBundleIDs.contains(bundleID) == false else { return nil }

        let appElement = AX.application(for: app.processIdentifier)
        AX.limitMessagingTimeout(appElement, seconds: 1.0)

        var target = AX.elementAttribute(appElement, AXAttr.focusedWindow)
        if target == nil {
            target = AX.windows(ofApplication: appElement).first
        }
        guard let window = target else { return nil }
        return snapshot(window: window, app: app, bundleID: bundleID)
    }

    /// 把一个 AX 窗口读成快照
    static func snapshot(window: AXUIElement,
                         app: NSRunningApplication,
                         bundleID: String,
                         displays: [DisplayInfo] = []) -> WindowSnapshot? {
        AX.limitMessagingTimeout(window, seconds: 1.0)
        guard let role = AX.string(window, AXAttr.role), role == AXRole.window else { return nil }
        guard let rect = AX.frame(of: window) else { return nil }
        return makeSnapshot(window: window,
                            app: app,
                            bundleID: bundleID,
                            role: role,
                            subrole: AX.string(window, AXAttr.subrole) ?? "",
                            rect: rect,
                            minimized: AX.bool(window, AXAttr.minimized) ?? false,
                            displays: displays.isEmpty ? ScreenGeometry.currentDisplays : displays)
    }

    /// 已经读好的属性 -> 快照。显示器列表由调用方传进来，避免重复查询。
    private static func makeSnapshot(window: AXUIElement,
                                     app: NSRunningApplication,
                                     bundleID: String,
                                     role: String,
                                     subrole: String,
                                     rect: CGRect,
                                     minimized: Bool,
                                     displays: [DisplayInfo]) -> WindowSnapshot {
        let display = ScreenGeometry.display(containing: rect, in: displays)
        let displayFrame = display?.frame ?? rect
        return WindowSnapshot(
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            title: AX.string(window, AXAttr.title) ?? "",
            role: role,
            subrole: subrole,
            frame: Frame(rect),
            displayID: display?.id ?? CGMainDisplayID(),
            displayUUID: display?.uuid,
            displayIndex: display?.index ?? 0,
            displayName: display?.name ?? "主显示器",
            displayFrame: Frame(displayFrame),
            relativeFrame: Frame(rect).relative(to: displayFrame),
            isMinimized: minimized,
            isFullScreen: AX.bool(window, AXAttr.fullScreen) ?? false,
            zIndex: 0)
    }

    // MARK: - 前后顺序

    /// CGWindowList 是「前面优先」的顺序，用它给窗口排个 z 序
    private final class ZOrderTable {
        private var entries: [(pid: pid_t, rect: CGRect, used: Bool)]

        init(_ list: [(pid: pid_t, rect: CGRect)]) {
            entries = list.map { (pid: $0.pid, rect: $0.rect, used: false) }
        }

        func value(pid: pid_t, rect: CGRect, fallback: Int) -> Int {
            for i in entries.indices {
                guard entries[i].used == false, entries[i].pid == pid else { continue }
                let candidate = entries[i].rect
                if abs(candidate.minX - rect.minX) <= 2,
                   abs(candidate.minY - rect.minY) <= 2,
                   abs(candidate.width - rect.width) <= 2,
                   abs(candidate.height - rect.height) <= 2 {
                    entries[i].used = true
                    return i
                }
            }
            return 1000 + fallback
        }
    }

    private static func windowZOrder() -> ZOrderTable {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return ZOrderTable([])
        }
        var list: [(pid: pid_t, rect: CGRect)] = []
        for info in raw {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = decode(bounds) else { continue }
            list.append((pid: pid_t(pidNumber.intValue), rect: rect))
        }
        return ZOrderTable(list)
    }

    private static func decode(_ dictionary: [String: Any]) -> CGRect? {
        guard let x = (dictionary["X"] as? NSNumber)?.doubleValue,
              let y = (dictionary["Y"] as? NSNumber)?.doubleValue,
              let w = (dictionary["Width"] as? NSNumber)?.doubleValue,
              let h = (dictionary["Height"] as? NSNumber)?.doubleValue else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
