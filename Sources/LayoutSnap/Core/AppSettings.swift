import Foundation
import Combine
import ServiceManagement

/// 用户偏好设置，直接落 UserDefaults
final class AppSettings: ObservableObject {

    static let shared = AppSettings()
    static let didChange = Notification.Name("com.layoutsnap.settingsChanged")

    private let defaults: UserDefaults
    private var loading = true

    // MARK: - 通用

    @Published var launchAtLogin: Bool = false {
        didSet { persist(); applyLaunchAtLogin() }
    }

    /// 等待应用启动/交出窗口的最长秒数
    @Published var appLaunchTimeout: Double = 15 {
        didSet { persist() }
    }

    /// 兼容模式：Electron / Chromium 系应用需要
    @Published var compatibilityMode: Bool = true {
        didSet { persist() }
    }

    /// 恢复之后按原来的前后顺序重新叠放窗口
    @Published var restoreStackingOrder: Bool = true {
        didSet { persist() }
    }

    /// 保存时是全屏的窗口，恢复时也切回全屏
    @Published var restoreFullScreenWindows: Bool = false {
        didSet { persist() }
    }

    /// 恢复结果显示在菜单栏
    @Published var showResultInMenuBar: Bool = true {
        didSet { persist() }
    }

    /// 并行处理的应用数量上限。
    /// 扫描和恢复都是「按应用」并行的，同一个应用内部保持串行。
    @Published var parallelWorkers: Int = 4 {
        didSet { persist() }
    }

    /// 忽略这些应用（bundle id，换行或逗号分隔）
    @Published var excludedBundleIDsText: String = "" {
        didSet { persist() }
    }

    /// 最近一次用过的布局。「恢复布局」的快捷键默认恢复它。
    @Published var lastUsedLayoutID: String = "" {
        didSet { persist() }
    }

    /// 全局动作的快捷键（只有「恢复布局」默认有 ⌃Z，其他等用户自己设）
    @Published private(set) var actionHotKeys: [String: HotKeySpec] = [:]

    func hotKey(for action: AppAction) -> HotKeySpec? {
        actionHotKeys[action.id]
    }

    func setHotKey(_ spec: HotKeySpec?, for action: AppAction) {
        var updated = actionHotKeys
        if let spec {
            updated[action.id] = spec
        } else {
            updated.removeValue(forKey: action.id)
        }
        actionHotKeys = updated
        guard loading == false else { return }
        persistActionHotKeys()
    }

    /// 1.0.3 之前「保存当前窗口 / 保存部分窗口」的键名，
    /// 现在分别对应「添加当前窗口 / 添加部分窗口」，读配置时迁移过来
    private static func migrateActionKeys(_ stored: [String: HotKeySpec]) -> [String: HotKeySpec] {
        var migrated: [String: HotKeySpec] = [:]
        for (key, spec) in stored {
            let newKey: String
            switch key {
            case "saveCurrentWindow": newKey = "addCurrentWindow"
            case "savePartialWindows": newKey = "addPartialWindows"
            default: newKey = key
            }
            migrated[newKey] = spec
        }
        return migrated
    }

    private func persistActionHotKeys() {
        if let data = try? JSONEncoder().encode(actionHotKeys) {
            defaults.set(data, forKey: "actionHotKeys")
        }
        NotificationCenter.default.post(name: AppSettings.didChange, object: nil)
    }

    // MARK: - 自动恢复

    /// 显示器配置变化（插拔外接屏、改分辨率）时自动恢复
    @Published var autoRestoreOnDisplayChange: Bool = false {
        didSet { persist() }
    }

    /// 上面的自动恢复用哪个布局
    @Published var displayChangeLayoutID: String = "" {
        didSet { persist() }
    }

    /// 布局里配置的「触发应用」启动时自动恢复
    @Published var autoRestoreOnAppLaunch: Bool = false {
        didSet { persist() }
    }

    // MARK: - 生命周期

    private convenience init() {
        AppSettings.migrateLegacyDefaultsIfNeeded(into: .standard)
        self.init(defaults: .standard)
    }

    /// 老版本的 bundle id 是 com.local.windowsnap，改名后新域是空的，
    /// 这里把旧设置搬一次（只搬认识的键，避免带入无关数据）。
    private static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        guard defaults.object(forKey: "hasShownWelcome") == nil else { return }
        guard let legacy = UserDefaults(suiteName: "com.local.windowsnap") else { return }

        let keys = ["launchAtLogin", "appLaunchTimeout", "compatibilityMode", "restoreStackingOrder",
                    "restoreFullScreenWindows", "showResultInMenuBar", "parallelWorkers",
                    "excludedBundleIDsText", "autoRestoreOnDisplayChange", "displayChangeLayoutID",
                    "autoRestoreOnAppLaunch", "lastUsedLayoutID", "actionHotKeys", "hasShownWelcome"]
        var migrated = 0
        for key in keys {
            guard let value = legacy.object(forKey: key) else { continue }
            defaults.set(value, forKey: key)
            migrated += 1
        }
        if migrated > 0 {
            Log.info("已从旧版本迁移 \(migrated) 项设置")
        }
    }

    /// 指定 UserDefaults 的实例（自检/测试用，免得动到用户真实设置）
    init(defaults: UserDefaults) {
        self.defaults = defaults
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        if defaults.object(forKey: "appLaunchTimeout") != nil {
            appLaunchTimeout = defaults.double(forKey: "appLaunchTimeout")
        }
        if defaults.object(forKey: "compatibilityMode") != nil {
            compatibilityMode = defaults.bool(forKey: "compatibilityMode")
        }
        if defaults.object(forKey: "restoreStackingOrder") != nil {
            restoreStackingOrder = defaults.bool(forKey: "restoreStackingOrder")
        }
        if defaults.object(forKey: "restoreFullScreenWindows") != nil {
            restoreFullScreenWindows = defaults.bool(forKey: "restoreFullScreenWindows")
        }
        if defaults.object(forKey: "showResultInMenuBar") != nil {
            showResultInMenuBar = defaults.bool(forKey: "showResultInMenuBar")
        }
        if defaults.object(forKey: "parallelWorkers") != nil {
            parallelWorkers = max(1, min(8, defaults.integer(forKey: "parallelWorkers")))
        }
        excludedBundleIDsText = defaults.string(forKey: "excludedBundleIDsText") ?? ""
        autoRestoreOnDisplayChange = defaults.bool(forKey: "autoRestoreOnDisplayChange")
        if defaults.object(forKey: "autoRestoreOnAppLaunch") != nil {
            autoRestoreOnAppLaunch = defaults.bool(forKey: "autoRestoreOnAppLaunch")
        }
        displayChangeLayoutID = defaults.string(forKey: "displayChangeLayoutID") ?? ""
        lastUsedLayoutID = defaults.string(forKey: "lastUsedLayoutID") ?? ""

        if let data = defaults.data(forKey: "actionHotKeys"),
           let decoded = try? JSONDecoder().decode([String: HotKeySpec].self, from: data) {
            actionHotKeys = AppSettings.migrateActionKeys(decoded)
        } else {
            // 第一次运行：只给「恢复布局」放上 ⌃Z
            var seeds: [String: HotKeySpec] = [:]
            for action in AppAction.allCases {
                if let spec = action.defaultHotKey { seeds[action.id] = spec }
            }
            actionHotKeys = seeds
        }

        loading = false
    }

    private func persist() {
        guard !loading else { return }
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(appLaunchTimeout, forKey: "appLaunchTimeout")
        defaults.set(compatibilityMode, forKey: "compatibilityMode")
        defaults.set(restoreStackingOrder, forKey: "restoreStackingOrder")
        defaults.set(restoreFullScreenWindows, forKey: "restoreFullScreenWindows")
        defaults.set(showResultInMenuBar, forKey: "showResultInMenuBar")
        defaults.set(parallelWorkers, forKey: "parallelWorkers")
        defaults.set(excludedBundleIDsText, forKey: "excludedBundleIDsText")
        defaults.set(autoRestoreOnDisplayChange, forKey: "autoRestoreOnDisplayChange")
        defaults.set(displayChangeLayoutID, forKey: "displayChangeLayoutID")
        defaults.set(lastUsedLayoutID, forKey: "lastUsedLayoutID")
        defaults.set(autoRestoreOnAppLaunch, forKey: "autoRestoreOnAppLaunch")
        NotificationCenter.default.post(name: AppSettings.didChange, object: nil)
    }

    // MARK: - 派生

    /// 用户点选忽略的应用（保持添加顺序、自动去重）
    var excludedAppList: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let separators = CharacterSet(charactersIn: ",\n\r ;")
        for piece in excludedBundleIDsText.components(separatedBy: separators) {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if seen.contains(trimmed) { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    var excludedBundleIDs: Set<String> {
        Set(excludedAppList)
    }

    func addExcludedApp(_ bundleID: String) {
        guard bundleID.isEmpty == false else { return }
        var list = excludedAppList
        for item in list where item == bundleID { return }
        list.append(bundleID)
        excludedBundleIDsText = list.joined(separator: "\n")
    }

    func removeExcludedApp(_ bundleID: String) {
        var list = excludedAppList
        list.removeAll { $0 == bundleID }
        excludedBundleIDsText = list.joined(separator: "\n")
    }

    func toggleExcludedApp(_ bundleID: String) {
        if excludedBundleIDs.contains(bundleID) {
            removeExcludedApp(bundleID)
        } else {
            addExcludedApp(bundleID)
        }
    }

    var displayChangeLayoutUUID: UUID? {
        UUID(uuidString: displayChangeLayoutID)
    }

    var restorerOptions: WindowRestorer.Options {
        var options = WindowRestorer.Options()
        options.appLaunchTimeout = appLaunchTimeout
        options.compatibilityMode = compatibilityMode
        options.restoreStackingOrder = restoreStackingOrder
        options.restoreFullScreenWindows = restoreFullScreenWindows
        options.maxConcurrentApps = parallelWorkers
        return options
    }

    // MARK: - 登录时启动

    func applyLaunchAtLogin() {
        guard !loading else { return }
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                Log.error("设置开机自启失败: \(error.localizedDescription)")
            }
        }
    }

    var launchAtLoginStatusText: String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return "已开启"
            case .notRegistered: return "未开启"
            case .requiresApproval: return "等待系统批准（系统设置 › 通用 › 登录项）"
            case .notFound: return "不可用（请把 App 放进「应用程序」文件夹）"
            @unknown default: return "未知"
            }
        }
        return "系统版本过低"
    }
}
