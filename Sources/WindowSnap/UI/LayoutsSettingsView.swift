import SwiftUI
import AppKit

/// 应用图标缓存（各个界面都用得到）
enum IconCache {
    private static var cache: [String: NSImage] = [:]
    private static let fallback = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) ?? NSImage()

    static func icon(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        var image = fallback
        if let url = AppLauncher.bundleURL(for: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        image.size = NSSize(width: 16, height: 16)
        cache[bundleID] = image
        return image
    }
}

struct LayoutsSettingsView: View {
    @ObservedObject var store: LayoutStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AppController
    /// 选中项放在 navigation 里，这样菜单栏的「编辑布局…」能直接跳到某个布局
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        HSplitView {
            sidebar
            detail
        }
        .onAppear {
            if navigation.selectedLayoutID == nil {
                navigation.selectedLayoutID = store.layouts.first?.id
            }
        }
        .onChange(of: store.layouts.count) { _ in
            if let current = navigation.selectedLayoutID, store.layout(id: current) == nil {
                navigation.selectedLayoutID = store.layouts.first?.id
            } else if navigation.selectedLayoutID == nil {
                navigation.selectedLayoutID = store.layouts.first?.id
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            if store.layouts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("还没有布局")
                        .foregroundStyle(.secondary)
                    Button("保存当前窗口布局") { controller.saveCurrentWindowLayout() }
                    Button("保存部分窗口布局") { controller.savePartialWindowsLayout() }
                    Button("保存所有窗口布局") { controller.saveAllWindowsLayout() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $navigation.selectedLayoutID) {
                    ForEach(store.layouts) { layout in
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.3.group")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(layout.displayName).font(.headline)
                                Text("\(layout.windows.count) 个窗口 · \(layout.appSummary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let hotKey = layout.hotKey {
                                Text(hotKey.display)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(layout.id)
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack(spacing: 8) {
                Menu {
                    Menu("保存当前窗口布局") {
                        ForEach(store.layouts) { layout in
                            Button("存进「\(layout.displayName)」") {
                                controller.saveCurrentWindow(into: layout)
                            }
                        }
                        if store.layouts.isEmpty == false { Divider() }
                        Button("新建布局…") { controller.saveCurrentWindowLayout() }
                    }
                    Menu("保存部分窗口布局") {
                        ForEach(store.layouts) { layout in
                            Button("存进「\(layout.displayName)」") {
                                controller.savePartialWindows(into: layout)
                            }
                        }
                        if store.layouts.isEmpty == false { Divider() }
                        Button("新建布局…") { controller.savePartialWindowsLayout() }
                    }
                    Menu("保存所有窗口布局") {
                        ForEach(store.layouts) { layout in
                            Button("存进「\(layout.displayName)」") {
                                controller.saveAllWindows(into: layout)
                            }
                        }
                        if store.layouts.isEmpty == false { Divider() }
                        Button("新建布局…") { controller.saveAllWindowsLayout() }
                    }
                } label: {
                    Label("保存布局", systemImage: "plus")
                }
                .frame(width: 110)
                Spacer()
            }
            .padding(8)
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
    }

    @ViewBuilder
    private var detail: some View {
        if let layout = selectedLayout {
            LayoutDetailView(layout: layout, store: store, settings: settings, controller: controller)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "hand.point.left")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("选择左边的一个布局")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedLayout: Layout? {
        guard let selected = navigation.selectedLayoutID else { return store.layouts.first }
        return store.layout(id: selected)
    }
}

struct LayoutDetailView: View {
    let layout: Layout
    @ObservedObject var store: LayoutStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AppController

    @State private var runningApps: [(bundleID: String, name: String)] = []
    @State private var collapsedApps: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                windowsSection
                Divider()
                triggersSection
            }
            .padding(14)
        }
        .onAppear { refreshRunningApps() }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("布局名称", text: Binding(
                get: { layout.name },
                set: { store.rename(id: layout.id, to: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.title3)

            HStack(spacing: 10) {
                Button {
                    controller.restore(layout: layout)
                } label: {
                    Label("恢复这个布局", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isRestoring)

                Button {
                    controller.updateLayout(layout)
                } label: {
                    Label("更新布局", systemImage: "arrow.clockwise")
                }

                Button {
                    controller.duplicateLayout(layout)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    controller.deleteLayout(layout)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "command").foregroundStyle(.secondary)
                if let hotKey = layout.hotKey {
                    Text(hotKey.display)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
                } else {
                    Text("没有设置快捷键")
                        .foregroundStyle(.secondary)
                }
                Button("去快捷键设置") {
                    controller.openSettings(tab: .shortcuts)
                }
                .buttonStyle(.link)

                Spacer()

                Text("最后更新 \(formatted(layout.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 窗口列表

    private var disabledCount: Int {
        layout.windows.filter { $0.isEnabled == false }.count
    }

    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if layout.windows.isEmpty == false {
                    enabledCheckbox(layout.windows)
                }
                Text("包含的窗口（\(layout.windows.count)）").font(.headline)
                if disabledCount > 0 {
                    Text("\(disabledCount) 个已停用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    controller.openWindowPicker(purpose: .append(layout: layout))
                } label: {
                    Label("添加窗口…", systemImage: "macwindow.badge.plus")
                }
            }

            if layout.windows.isEmpty {
                Text("这个布局里还没有窗口。点「添加窗口…」从当前打开的窗口里挑一个加进来。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(layout.windowsByApp, id: \.bundleID) { group in
                appGroup(group)
            }
        }
    }

    private func appGroup(_ group: (bundleID: String, appName: String, windows: [WindowSnapshot])) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    if collapsedApps.contains(group.bundleID) {
                        collapsedApps.remove(group.bundleID)
                    } else {
                        collapsedApps.insert(group.bundleID)
                    }
                } label: {
                    Image(systemName: collapsedApps.contains(group.bundleID) ? "chevron.right" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                enabledCheckbox(group.windows)
                Image(nsImage: IconCache.icon(for: group.bundleID))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(group.appName).font(.headline)
                Text("\(group.windows.count) 个窗口")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("删除本应用") {
                    deleteApp(group)
                }
                .buttonStyle(.link)
            }

            if collapsedApps.contains(group.bundleID) == false {
                ForEach(group.windows) { snapshot in
                    windowRow(snapshot)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor).opacity(0.7)))
    }

    private func windowRow(_ snapshot: WindowSnapshot) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { snapshot.isEnabled },
                set: { store.setWindowsEnabled($0, ids: Set<UUID>([snapshot.id]), in: layout.id) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.displayTitle).lineLimit(1)
                Text(snapshot.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                controller.restoreWindow(snapshot, in: layout)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("只把这一个窗口移回原位")
            .disabled(controller.isRestoring)

            Button {
                controller.syncWindowFromCurrent(snapshot, in: layout)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .help("把窗口现在的位置和尺寸同步到这条记录")

            Button {
                controller.editWindow(snapshot, in: layout)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑坐标、尺寸、匹配关键词")

            Button {
                store.moveWindow(id: snapshot.id, direction: -1, in: layout.id)
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .help("往前放（恢复时叠放更靠前）")

            Button {
                store.moveWindow(id: snapshot.id, direction: 1, in: layout.id)
            } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.borderless)
            .help("往后放")

            Button {
                store.removeWindows(ids: Set<UUID>([snapshot.id]), from: layout.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("从这个布局里删掉（不会关闭窗口）")
        }
        .padding(.vertical, 2)
        .padding(.leading, 18)
        .opacity(snapshot.isEnabled ? 1 : 0.45)
    }

    /// 三态复选框：全开 / 全关 / 部分开。
    /// 点和「每行的小勾选框」是同一个操作，只是作用于整组，避免出现两套重复的开关。
    @ViewBuilder
    private func enabledCheckbox(_ windows: [WindowSnapshot]) -> some View {
        let enabledCount = windows.filter { $0.isEnabled }.count
        let allOn = windows.isEmpty == false && enabledCount == windows.count
        let allOff = enabledCount == 0
        Button {
            store.setWindowsEnabled(allOn == false, ids: Set(windows.map(\.id)), in: layout.id)
        } label: {
            Image(systemName: allOn ? "checkmark.square.fill" : (allOff ? "square" : "minus.square.fill"))
                .foregroundStyle(allOn ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
    }

    private func deleteApp(_ group: (bundleID: String, appName: String, windows: [WindowSnapshot])) {
        let alert = NSAlert()
        alert.messageText = "把「\(group.appName)」从布局「\(layout.displayName)」里删掉？"
        alert.informativeText = "会删掉这个应用在布局里的 \(group.windows.count) 条窗口记录。不会关闭、也不会移动任何真实窗口。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let removed = store.removeApp(bundleID: group.bundleID, from: layout.id)
            controller.statusBar?.flash("已从布局里移除 \(group.appName) 的 \(removed) 个窗口")
        }
    }

    // MARK: - 触发应用

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("触发应用").font(.headline)
            Text("这些应用启动时，如果打开了「自动恢复」，就会自动恢复本布局。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if layout.triggerBundleIDs.isEmpty {
                Text("（未设置）").font(.caption).foregroundStyle(.secondary)
            }

            ForEach(layout.triggerBundleIDs, id: \.self) { bundleID in
                HStack(spacing: 8) {
                    Image(nsImage: IconCache.icon(for: bundleID))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(AppLauncher.appName(for: bundleID))
                    Text(bundleID).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        var list = layout.triggerBundleIDs
                        list.removeAll { $0 == bundleID }
                        store.setTriggers(list, for: layout.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Menu {
                if runningApps.isEmpty {
                    Text("没有正在运行的应用")
                }
                ForEach(runningApps, id: \.bundleID) { app in
                    Button(app.name) {
                        var list = layout.triggerBundleIDs
                        if list.contains(app.bundleID) == false { list.append(app.bundleID) }
                        store.setTriggers(list, for: layout.id)
                    }
                }
                Divider()
                Button("刷新列表") { refreshRunningApps() }
            } label: {
                Label("添加应用…", systemImage: "plus")
            }
            .frame(width: 140)
        }
    }

    private func refreshRunningApps() {
        runningApps = AppLauncher.installedRegularApplications()
            .filter { layout.triggerBundleIDs.contains($0.bundleID) == false }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
