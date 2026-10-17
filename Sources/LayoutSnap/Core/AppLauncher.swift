import Foundation
import AppKit

/// 负责「应用没开就帮你开起来」
enum AppLauncher {

    static func runningPID(_ bundleID: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { !$0.isTerminated })?
            .processIdentifier
    }

    static func isRunning(_ bundleID: String) -> Bool {
        runningPID(bundleID) != nil
    }

    @discardableResult
    static func launch(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Log.error("找不到应用: \(bundleID)")
            return false
        }
        markLaunchedByUs(bundleID)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Log.error("启动 \(bundleID) 失败: \(error.localizedDescription)")
            } else {
                success = true
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return success || isRunning(bundleID)
    }

    /// 确保应用在跑，返回 pid
    static func ensureRunning(bundleID: String,
                              timeout: TimeInterval,
                              progress: ((String) -> Void)? = nil) -> pid_t? {
        if let pid = runningPID(bundleID) { return pid }

        progress?("正在启动 \(appName(for: bundleID))…")
        guard launch(bundleID) else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let pid = runningPID(bundleID) { return pid }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return runningPID(bundleID)
    }

    static func appName(for bundleID: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    static func bundleURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    // MARK: - 「是我们自己拉起来的」

    // 恢复布局时如果顺手启动了某个应用，而这个应用恰好又是某个布局的
    // 触发应用，就会无限套娃。这里记一笔，触发逻辑会忽略掉。

    private static let launchLock = NSLock()
    private static var launchTimestamps: [String: Date] = [:]

    static func markLaunchedByUs(_ bundleID: String) {
        launchLock.lock()
        defer { launchLock.unlock() }
        launchTimestamps[bundleID] = Date()
    }

    static func wasLaunchedByUsRecently(_ bundleID: String, within: TimeInterval = 60) -> Bool {
        launchLock.lock()
        defer { launchLock.unlock() }
        launchTimestamps = launchTimestamps.filter { Date().timeIntervalSince($0.value) < within }
        return launchTimestamps[bundleID] != nil
    }

    /// 当前所有「有 Dock 图标」的应用（用于选择触发应用）
    static func installedRegularApplications() -> [(bundleID: String, name: String)] {
        var seen = Set<String>()
        var result: [(String, String)] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, let bundleID = app.bundleIdentifier else { continue }
            guard !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            result.append((bundleID, app.localizedName ?? bundleID))
        }
        return result.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }
}
