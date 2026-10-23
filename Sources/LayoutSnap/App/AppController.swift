import Foundation
import AppKit
import Combine

/// 应用的大脑：把「菜单 / 热键 / 通知」这些入口都收敛到这里
final class AppController: ObservableObject {

    static let shared = AppController()

    let store = LayoutStore.shared
    let settings = AppSettings.shared
    let restorer = WindowRestorer()

    @Published private(set) var isRestoring = false
    private(set) var lastReport: RestoreReport?
    private(set) var lastRestoredLayoutID: UUID?

    var statusBar: StatusBarController?
    private var windowPicker: WindowPickerWindowController?
    private var windowEditors: [WindowEntryEditorController] = []
    private lazy var settingsWindow = SettingsWindowController(store: store, settings: settings, controller: self)

    /// 全局动作的热键 id 前缀，用来和布局 id（UUID 字符串）区分
    static let actionPrefix = "action:"

    private var currentBindings: [HotKeyBinding] = []
    private var hotKeysSuspended = false

    private var cancellables = Set<AnyCancellable>()
    private var scanning = false
    private var lastPermissionState = AX.isTrusted

    private init() {}

    // MARK: - 启动

    func start() {
        Log.rotateIfNeeded()

        // 布局变了就重新注册热键。用 removeDuplicates 过滤掉「只改了名字/窗口」
        // 这类不影响热键的变更，避免打字时反复注销再注册。
        Publishers.CombineLatest(store.$layouts, settings.$actionHotKeys)
            .map { layouts, actionHotKeys -> [HotKeyBinding] in
                var bindings: [HotKeyBinding] = []
                for layout in layouts {
                    guard let spec = layout.hotKey else { continue }
                    bindings.append(HotKeyBinding(id: layout.id.uuidString, spec: spec))
                }
                for action in AppAction.allCases {
                    guard let spec = actionHotKeys[action.id] else { continue }
                    bindings.append(HotKeyBinding(id: AppController.actionPrefix + action.id, spec: spec))
                }
                return bindings
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bindings in
                self?.applyHotKeyBindings(bindings)
            }
            .store(in: &cancellables)

        // 显示器配置变化 -> 自动恢复（插拔外接屏的重灾区）
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(2.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleDisplayConfigurationChange() }
            .store(in: &cancellables)

        // 触发应用启动 -> 自动恢复
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }
                self?.handleApplicationLaunch(bundleID: bundleID)
            }
            .store(in: &cancellables)

        // 唤醒后把窗口拉回来（外接屏可能换了）
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleWake() }
            .store(in: &cancellables)

        HotKeyCenter.shared.onTrigger = { [weak self] bindingID in
            self?.handleHotKey(bindingID: bindingID)
        }

        // 辅助功能权限是随时可能被用户改的，变了就更新菜单栏图标（✋ -> 正常）
        Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let trusted = AX.isTrusted
                if trusted != self.lastPermissionState {
                    self.lastPermissionState = trusted
                    Log.info("辅助功能权限状态变为：\(trusted ? "已授权" : "未授权")")
                    self.statusBar?.refreshIdleState()
                }
            }
            .store(in: &cancellables)

        statusBar?.refreshIdleState()

        if !AX.isTrusted {
            AX.requestPermissionPrompt()
        }
    }

    func shutdown() {
        HotKeyCenter.shared.teardown()
    }

    // MARK: - 全局动作

    private func handleHotKey(bindingID: String) {
        if bindingID.hasPrefix(AppController.actionPrefix) {
            let raw = String(bindingID.dropFirst(AppController.actionPrefix.count))
            guard let action = AppAction(rawValue: raw) else { return }
            perform(action)
            return
        }
        guard let layoutID = UUID(uuidString: bindingID),
              let layout = store.layout(id: layoutID) else { return }
        restore(layout: layout)
    }

    /// 快捷键「添加当前窗口」：加到最近使用的布局；还没有可用布局时新建一个
    private func addCurrentWindowToRecentLayout() {
        if let layout = lastUsedLayout {
            appendCurrentWindow(to: layout)
        } else {
            saveCurrentWindowLayout()
        }
    }

    /// 快捷键「添加部分窗口」：同上，挑好窗口后加到最近使用的布局
    private func addPartialWindowsToRecentLayout() {
        if let layout = lastUsedLayout {
            appendPartialWindows(to: layout)
        } else {
            savePartialWindowsLayout()
        }
    }

    /// 快捷键「保存部分窗口」：挑好窗口后整体覆盖最近使用的布局
    private func replacePartialWindowsInRecentLayout() {
        if let layout = lastUsedLayout {
            replacePartialWindows(in: layout)
        } else {
            replacePartialWindowsLayout()
        }
    }

    private func applyHotKeyBindings(_ bindings: [HotKeyBinding]) {
        currentBindings = bindings
        guard hotKeysSuspended == false else { return }
        HotKeyCenter.shared.reload(bindings)
    }

    /// 录制快捷键时先把所有全局热键停掉，免得录到一半把原动作触发了
    func setHotKeysSuspended(_ suspended: Bool) {
        hotKeysSuspended = suspended
        HotKeyCenter.shared.reload(suspended ? [] : currentBindings)
    }

    /// 设置某个功能的快捷键（会把别处占用的同一个组合键先解绑）
    func setHotKey(_ spec: HotKeySpec?, for action: AppAction) {
        if let spec {
            clearConflicts(with: spec, exceptAction: action, exceptLayout: nil)
        }
        settings.setHotKey(spec, for: action)
    }

    /// 设置某个布局的快捷键
    func setHotKey(_ spec: HotKeySpec?, for layout: Layout) {
        if let spec {
            clearConflicts(with: spec, exceptAction: nil, exceptLayout: layout.id)
        }
        store.setHotKey(spec, for: layout.id)
    }

    private func clearConflicts(with spec: HotKeySpec, exceptAction: AppAction?, exceptLayout: UUID?) {
        for action in AppAction.allCases where action != exceptAction {
            guard let existing = settings.hotKey(for: action), existing.conflicts(with: spec) else { continue }
            settings.setHotKey(nil, for: action)
        }
        for layout in store.layouts where layout.id != exceptLayout {
            guard let existing = layout.hotKey, existing.conflicts(with: spec) else { continue }
            store.setHotKey(nil, for: layout.id)
        }
    }

    func perform(_ action: AppAction) {
        switch action {
        case .restoreLayout:
            restoreLastUsedLayout()
        case .addCurrentWindow:
            addCurrentWindowToRecentLayout()
        case .addPartialWindows:
            addPartialWindowsToRecentLayout()
        case .savePartialWindows:
            replacePartialWindowsInRecentLayout()
        case .saveAllWindows:
            saveAllWindowsLayout()
        }
    }

    // MARK: - 权限

    var hasPermission: Bool { AX.isTrusted }

    func requestPermission() {
        AX.requestPermissionPrompt()
        AX.openAccessibilitySettings()
    }

    func requirePermission() -> Bool {
        if AX.isTrusted { return true }
        let alert = NSAlert()
        alert.messageText = "需要「辅助功能」权限"
        alert.informativeText = "布局快照 需要辅助功能权限才能读取和恢复窗口的位置与大小。\n\n请到「系统设置 › 隐私与安全性 › 辅助功能」里勾选 布局快照（添加之后需要重启本应用才生效）。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后再说")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            requestPermission()
        }
        return false
    }

    // MARK: - 保存 / 更新

    func scanCurrentWindows(completion: @escaping ([WindowSnapshot]) -> Void) {
        guard !scanning else { return }
        scanning = true
        statusBar?.showBusy("正在扫描窗口…")
        let excluded = settings.excludedBundleIDs
        let maxWorkers = settings.parallelWorkers
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var options = ScanOptions()
            options.excludedBundleIDs = excluded
            options.maxConcurrentApps = maxWorkers
            let snapshots = WindowScanner.snapshot(options: options)
            DispatchQueue.main.async {
                self?.scanning = false
                // 扫描一结束就把菜单栏图标收回来：用户在后面的弹窗里点「取消」时，
                // 图标不该一直卡在「正在扫描」上
                self?.statusBar?.refreshIdleState()
                completion(snapshots)
            }
        }
    }

    func saveAllWindowsLayout() {
        guard requirePermission() else { return }
        scanCurrentWindows { [weak self] snapshots in
            guard let self else { return }
            guard !snapshots.isEmpty else {
                self.simpleAlert(title: "没有可保存的窗口",
                                 message: "没有扫描到任何窗口。请确认 布局快照 已经拿到辅助功能权限，并且当前确实有打开的窗口。")
                return
            }
            let defaultName = "布局 \(self.store.layouts.count + 1)"
            guard let name = self.askForText(title: "保存所有窗口布局",
                                             message: "把当前 \(snapshots.count) 个窗口的位置和大小存成一个布局，之后可以一键恢复。",
                                             placeholder: "给布局起个名字，例如「工作」「看片」",
                                             defaultValue: defaultName) else { return }
            let layout = self.store.add(name: name, windows: snapshots)
            self.statusBar?.flash("已保存「\(layout.name)」\(snapshots.count) 个窗口")
        }
    }

    /// 只保存当前正在用的那一个窗口（最前面应用的焦点窗口）
    func saveCurrentWindowLayout() {
        guard requirePermission() else { return }
        statusBar?.showBusy("正在读取当前窗口…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = WindowScanner.snapshotFrontmostWindow()
            DispatchQueue.main.async {
                guard let self else { return }
                self.statusBar?.refreshIdleState()
                guard let snapshot else {
                    self.statusBar?.flash("没找到当前窗口", state: .warning)
                    self.simpleAlert(title: "没找到当前窗口",
                                     message: "请先把要保存的那个窗口点到最前面，再试一次。")
                    return
                }
                let defaultName = "窗口 \(self.store.layouts.count + 1)"
                let summary = "\(snapshot.appName) · \(snapshot.displayTitle)"
                guard let name = self.askForText(title: "保存当前窗口布局",
                                                 message: "把「\(summary)」现在的窗口位置和大小存成一个布局。",
                                                 placeholder: "给这个布局起个名字",
                                                 defaultValue: defaultName) else { return }
                let layout = self.store.add(name: name, windows: [snapshot])
                self.statusBar?.flash("已保存「\(layout.displayName)」")
            }
        }
    }

    /// 新建一个由勾选窗口组成的布局（「添加部分窗口」「保存部分窗口」的新建流程相同）
    func savePartialWindowsLayout() {
        guard requirePermission() else { return }
        let defaultName = "布局 \(store.layouts.count + 1)"
        guard let name = askForText(title: "新建布局",
                                    message: "先给布局起个名字，下一步再勾选要放进去的窗口。",
                                    placeholder: "给这个布局起个名字",
                                    defaultValue: defaultName) else { return }
        openWindowPicker(purpose: .createNew(name: name))
    }

    /// 「保存部分窗口」的新建流程：同样先起名再挑窗口
    func replacePartialWindowsLayout() {
        savePartialWindowsLayout()
    }

    // MARK: - 添加到已有布局（追加）

    /// 把当前窗口加到指定布局里，布局中其他窗口记录保持不动
    func appendCurrentWindow(to layout: Layout) {
        guard requirePermission() else { return }
        statusBar?.showBusy("正在读取当前窗口…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = WindowScanner.snapshotFrontmostWindow()
            DispatchQueue.main.async {
                guard let self else { return }
                self.statusBar?.refreshIdleState()
                guard let snapshot else {
                    self.statusBar?.flash("没找到当前窗口", state: .warning)
                    self.simpleAlert(title: "没找到当前窗口",
                                     message: "请先把要保存的那个窗口点到最前面，再试一次。")
                    return
                }
                // 追加：同一个应用 + 同一标题的窗口已在布局里时，只更新它那一条
                self.store.addWindows([snapshot], to: layout.id)
                self.settings.lastUsedLayoutID = layout.id.uuidString
                self.statusBar?.flash("已把当前窗口添加到「\(layout.displayName)」")
            }
        }
    }

    // MARK: - 保存进已有布局（整体覆盖）

    /// 用当前所有窗口整体覆盖指定布局
    func replaceAllWindows(in layout: Layout) {
        guard requirePermission() else { return }
        scanCurrentWindows { [weak self] snapshots in
            guard let self else { return }
            guard snapshots.isEmpty == false else {
                self.statusBar?.flash("没有扫描到窗口", state: .warning)
                self.simpleAlert(title: "没有可保存的窗口",
                                 message: "没有扫描到任何窗口，布局未被修改。")
                return
            }
            self.store.replaceWindows(snapshots, in: layout.id)
            self.settings.lastUsedLayoutID = layout.id.uuidString
            self.statusBar?.flash("已用 \(snapshots.count) 个窗口覆盖「\(layout.displayName)」")
        }
    }

    /// 勾选窗口后加到指定布局里（追加）
    func appendPartialWindows(to layout: Layout) {
        openWindowPicker(purpose: .append(layout: layout))
    }

    /// 勾选窗口后整体覆盖指定布局
    func replacePartialWindows(in layout: Layout) {
        openWindowPicker(purpose: .replace(layout: layout))
    }

    /// 选择器里点了确认：按当初的意图落到对应的布局上
    func applyPickedWindows(_ snapshots: [WindowSnapshot], purpose: WindowPickerPurpose) {
        guard snapshots.isEmpty == false else { return }
        switch purpose {
        case .createNew(let name):
            let layout = store.add(name: name, windows: snapshots)
            statusBar?.flash("已保存「\(layout.displayName)」\(snapshots.count) 个窗口")
        case .append(let layout):
            let result = store.addWindows(snapshots, to: layout.id)
            settings.lastUsedLayoutID = layout.id.uuidString
            statusBar?.flash(addResultMessage(result, layout: layout))
        case .replace(let layout):
            store.replaceWindows(snapshots, in: layout.id)
            settings.lastUsedLayoutID = layout.id.uuidString
            statusBar?.flash("已用 \(snapshots.count) 个窗口覆盖「\(layout.displayName)」")
        }
    }

    func updateLayout(_ layout: Layout) {
        guard requirePermission() else { return }
        scanCurrentWindows { [weak self] snapshots in
            guard let self else { return }
            guard !snapshots.isEmpty else {
                self.statusBar?.flash("没有扫描到窗口", state: .warning)
                self.simpleAlert(title: "没有可保存的窗口", message: "没有扫描到任何窗口，布局未被修改。")
                return
            }
            self.store.update(id: layout.id, windows: snapshots)
            self.statusBar?.flash("已用当前窗口更新「\(layout.name)」")
        }
    }

    func renameLayout(_ layout: Layout) {
        guard let name = askForText(title: "重命名布局",
                                    message: "当前名字：\(layout.name)",
                                    placeholder: "新的名字",
                                    defaultValue: layout.name) else { return }
        store.rename(id: layout.id, to: name)
    }

    func deleteLayout(_ layout: Layout) {
        let alert = NSAlert()
        alert.messageText = "删除布局「\(layout.name)」？"
        alert.informativeText = "只删除保存的布局，不会关闭或移动任何窗口。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.remove(id: layout.id)
        }
    }

    func duplicateLayout(_ layout: Layout) {
        var copy = layout
        copy.id = UUID()
        copy.name = layout.name + " 副本"
        copy.hotKey = nil
        store.add(name: copy.name, windows: copy.windows, triggerBundleIDs: copy.triggerBundleIDs)
    }

    // MARK: - 恢复

    func restore(layout: Layout) {
        guard !isRestoring else {
            statusBar?.showBusy("正在恢复中，请稍等…")
            return
        }
        guard requirePermission() else { return }
        guard !layout.windows.isEmpty else {
            statusBar?.flash("「\(layout.name)」里没有窗口", state: .warning)
            return
        }

        isRestoring = true
        lastRestoredLayoutID = layout.id
        settings.lastUsedLayoutID = layout.id.uuidString
        statusBar?.rebuildMenu()
        statusBar?.showBusy("正在恢复「\(layout.name)」…")

        restorer.restore(layout: layout,
                         options: settings.restorerOptions,
                         progress: { [weak self] message in
                             self?.statusBar?.showBusy(message)
                         },
                         completion: { [weak self] report in
                             guard let self else { return }
                             self.isRestoring = false
                             self.lastReport = report
                             self.statusBar?.rebuildMenu()
                             self.statusBar?.flash("「\(layout.name)」\(report.summary)",
                                                   state: report.failed > 0 ? .warning : .success)
                             if !report.notes.isEmpty {
                                 Log.info("恢复备注: \(report.notes.joined(separator: "；"))")
                             }
                         })
    }

    /// 最近用过的那个布局（⌃Z 默认恢复它）
    var lastUsedLayout: Layout? {
        if let raw = UUID(uuidString: settings.lastUsedLayoutID), let layout = store.layout(id: raw) {
            return layout
        }
        if let id = lastRestoredLayoutID, let layout = store.layout(id: id) {
            return layout
        }
        return nil
    }

    /// 「恢复布局」这个全局动作：优先恢复最近用过的布局；
    /// 没有历史（或者布局被删了）就退回上一个；实在不行打开菜单让用户挑。
    func restoreLastUsedLayout() {
        if let layout = lastUsedLayout {
            restore(layout: layout)
            return
        }
        if store.layouts.count == 1, let only = store.layouts.first {
            restore(layout: only)
            return
        }
        guard store.layouts.isEmpty == false else {
            statusBar?.flash("还没有保存过布局", state: .warning)
            return
        }
        statusBar?.flash("请选择一个布局", state: .idle, duration: 2)
        statusBar?.openMenu()
    }

    // MARK: - 单个窗口

    /// 只把一个窗口搬回它该在的位置
    func restoreWindow(_ snapshot: WindowSnapshot, in layout: Layout) {
        guard isRestoring == false else {
            statusBar?.showBusy("正在恢复中，请稍等…")
            return
        }
        guard requirePermission() else { return }
        guard snapshot.isEnabled else {
            statusBar?.flash("「\(snapshot.displayTitle)」已停用", state: .warning)
            return
        }

        isRestoring = true
        lastRestoredLayoutID = layout.id
        statusBar?.showBusy("正在归位「\(snapshot.displayTitle)」…")

        restorer.restore(snapshots: [snapshot],
                         name: snapshot.displayTitle,
                         options: settings.restorerOptions,
                         progress: { [weak self] message in
                             self?.statusBar?.showBusy(message)
                         },
                         completion: { [weak self] report in
                             guard let self else { return }
                             self.isRestoring = false
                             self.lastReport = report
                             self.statusBar?.rebuildMenu()
                             self.statusBar?.flash("「\(snapshot.displayTitle)」\(report.summary)",
                                                   state: report.failed > 0 ? .warning : .success)
                         })
    }

    /// 读一下这个窗口现在真实的位置和尺寸
    func locateCurrentWindow(for snapshot: WindowSnapshot, completion: @escaping (WindowSnapshot?) -> Void) {
        guard requirePermission() else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let updated = WindowLocator.refresh(snapshot)
            DispatchQueue.main.async { completion(updated) }
        }
    }

    /// 用当前真实窗口的位置覆盖这条记录
    func syncWindowFromCurrent(_ snapshot: WindowSnapshot, in layout: Layout) {
        locateCurrentWindow(for: snapshot) { [weak self] updated in
            guard let self else { return }
            guard let updated else {
                self.simpleAlert(title: "没找到这个窗口",
                                 message: "「\(snapshot.displayTitle)」现在不在。\n请先把 \(snapshot.appName) 的窗口打开、摆到想要的位置，再回来更新。")
                return
            }
            self.store.updateWindow(updated, in: layout.id)
            self.statusBar?.flash("已用当前位置更新「\(snapshot.displayTitle)」")
        }
    }

    // MARK: - 挑选窗口

    /// 打开窗口选择器：可以从当前所有窗口里挑若干个（哪怕只有一个应用的一个窗口）
    func openWindowPicker(purpose: WindowPickerPurpose) {
        guard requirePermission() else { return }
        let picker = WindowPickerWindowController(controller: self)
        windowPicker = picker
        picker.onClose = { [weak self] in
            self?.windowPicker = nil
        }
        picker.show(purpose: purpose)
    }

    func saveSelectedWindowsAsLayout(_ snapshots: [WindowSnapshot]) {
        guard snapshots.isEmpty == false else { return }
        let defaultName = "布局 \(store.layouts.count + 1)"
        guard let name = askForText(title: "保存为新布局",
                                    message: "把选中的 \(snapshots.count) 个窗口存成一个新布局，之后可以一键恢复。",
                                    placeholder: "布局名字",
                                    defaultValue: defaultName) else { return }
        let layout = store.add(name: name, windows: snapshots)
        statusBar?.flash("已保存「\(layout.displayName)」\(snapshots.count) 个窗口")
    }

    func addWindows(_ snapshots: [WindowSnapshot], to layout: Layout) {
        guard snapshots.isEmpty == false else { return }
        let result = store.addWindows(snapshots, to: layout.id)
        settings.lastUsedLayoutID = layout.id.uuidString
        statusBar?.flash(addResultMessage(result, layout: layout))
    }

    /// 添加结果的提示：区分「新增」和「更新了已有记录」
    private func addResultMessage(_ result: (added: Int, updated: Int), layout: Layout) -> String {
        if result.added == 0 && result.updated > 0 {
            return "这 \(result.updated) 个窗口已在「\(layout.displayName)」中，已更新位置"
        }
        if result.updated == 0 {
            return "已往「\(layout.displayName)」加入 \(result.added) 个窗口"
        }
        return "已往「\(layout.displayName)」加入 \(result.added) 个窗口，更新 \(result.updated) 个"
    }

    // MARK: - 单个窗口的编辑窗口

    func editWindow(_ snapshot: WindowSnapshot, in layout: Layout) {
        let editor = WindowEntryEditorController(snapshot: snapshot,
                                                 layoutID: layout.id,
                                                 layoutName: layout.displayName,
                                                 controller: self)
        editor.onClose = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.windowEditors.removeAll { $0 === editor }
        }
        windowEditors.append(editor)
        editor.show()
    }

    // MARK: - 自动触发

    private func handleDisplayConfigurationChange() {
        ScreenGeometry.invalidateDisplayCache()
        guard settings.autoRestoreOnDisplayChange else { return }
        guard let id = settings.displayChangeLayoutUUID, let layout = store.layout(id: id) else { return }
        guard !isRestoring else { return }
        Log.info("显示器配置变化，自动恢复「\(layout.name)」")
        statusBar?.showBusy("显示器变化，自动恢复布局…")
        restore(layout: layout)
    }

    private func handleWake() {
        guard settings.autoRestoreOnDisplayChange else { return }
        guard let id = settings.displayChangeLayoutUUID, let layout = store.layout(id: id) else { return }
        guard !isRestoring else { return }
        // 唤醒后系统重新枚举显示器比较慢，等一会儿
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, !self.isRestoring else { return }
            Log.info("系统唤醒，自动恢复「\(layout.name)」")
            self.restore(layout: layout)
        }
    }

    private func handleApplicationLaunch(bundleID: String) {
        guard settings.autoRestoreOnAppLaunch else { return }
        guard !isRestoring else { return }
        if AppLauncher.wasLaunchedByUsRecently(bundleID) { return }
        let matches = store.layouts(triggeredBy: bundleID)
        guard let layout = matches.first else { return }
        Log.info("触发应用 \(bundleID) 启动，自动恢复「\(layout.name)」")
        // 等应用把窗口交出来
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.isRestoring else { return }
            self.restore(layout: layout)
        }
    }

    // MARK: - 设置窗口

    func openSettings(tab: SettingsTab = .general, layoutID: UUID? = nil) {
        settingsWindow.show(tab: tab, layoutID: layoutID)
    }

    // MARK: - 小工具

    func simpleAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func askForText(title: String, message: String, placeholder: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = placeholder
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? defaultValue : text
    }
}
