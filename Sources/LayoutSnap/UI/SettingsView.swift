import SwiftUI
import AppKit
import Combine

struct SettingsView: View {
    @ObservedObject var store: LayoutStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AppController
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettingsView(store: store, settings: settings, controller: controller)
                .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.symbol) }
                .tag(SettingsTab.general)

            LayoutsSettingsView(store: store, settings: settings, controller: controller, navigation: navigation)
                .tabItem { Label(SettingsTab.layouts.title, systemImage: SettingsTab.layouts.symbol) }
                .tag(SettingsTab.layouts)

            ShortcutsSettingsView(store: store, settings: settings, controller: controller)
                .tabItem { Label(SettingsTab.shortcuts.title, systemImage: SettingsTab.shortcuts.symbol) }
                .tag(SettingsTab.shortcuts)

            AboutSettingsView(store: store, controller: controller)
                .tabItem { Label(SettingsTab.about.title, systemImage: SettingsTab.about.symbol) }
                .tag(SettingsTab.about)
        }
        .padding(14)
        .frame(minWidth: 700, minHeight: 460)
    }
}

// MARK: - 通用

struct GeneralSettingsView: View {
    @ObservedObject var store: LayoutStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AppController

    @State private var trusted = AX.isTrusted

    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trusted ? "辅助功能权限已获得" : "缺少辅助功能权限")
                            .font(.headline)
                        Text(trusted
                             ? "布局快照 可以读写窗口的位置和大小了。"
                             : "没有这个权限，扫描和恢复窗口都会失败。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(trusted ? "打开系统设置" : "去授权") {
                        controller.requestPermission()
                    }
                }
            }

            Section("启动") {
                Toggle("开机自动启动", isOn: $settings.launchAtLogin)
                Text(settings.launchAtLoginStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("恢复行为") {
                Toggle("兼容模式（Electron / Chromium 系应用）", isOn: $settings.compatibilityMode)
                Text("Chrome、VS Code、Slack 这类应用默认会忽略移动窗口的请求，打开兼容模式可解决。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("恢复窗口的前后叠放顺序", isOn: $settings.restoreStackingOrder)
                Toggle("保存时全屏的窗口，恢复时也切回全屏", isOn: $settings.restoreFullScreenWindows)

                HStack {
                    Text("启动应用时的等待时间")
                    Slider(value: $settings.appLaunchTimeout, in: 5...60, step: 1) {
                        Text("等待")
                    }
                    .frame(width: 180)
                    Text("\(Int(settings.appLaunchTimeout)) 秒")
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
                Text("恢复布局时如果需要先打开某个应用，会等它把窗口交出来，最多等这么久。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("并行处理的应用数")
                    Slider(value: Binding(
                        get: { Double(settings.parallelWorkers) },
                        set: { settings.parallelWorkers = Int($0.rounded()) }
                    ), in: 1...8, step: 1)
                    .frame(width: 180)
                    Text("\(settings.parallelWorkers)")
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
                Text("扫描和恢复都是按应用并行的（同一个应用内部仍然串行，避免它自己的窗口管理逻辑打架）。"
                     + "窗口多的时候调大更快，但也更吃 CPU；默认 4 通常够用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("自动恢复") {
                Toggle("显示器配置变化时自动恢复", isOn: $settings.autoRestoreOnDisplayChange)
                if settings.autoRestoreOnDisplayChange {
                    Picker("使用布局", selection: $settings.displayChangeLayoutID) {
                        Text("请选择").tag("")
                        ForEach(store.layouts) { layout in
                            Text(layout.displayName).tag(layout.id.uuidString)
                        }
                    }
                    Text("插拔外接显示器、合盖唤醒、修改分辨率后，自动把窗口恢复到该布局。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("布局的「触发应用」启动时自动恢复", isOn: $settings.autoRestoreOnAppLaunch)
                Text("在「布局」标签页里可以给每个布局指定触发应用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("忽略的应用") {
                ExcludedAppsView(settings: settings, controller: controller)
            }

            Section("菜单栏") {
                Toggle("在菜单栏显示操作结果", isOn: $settings.showResultInMenuBar)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            trusted = AX.isTrusted
        }
    }
}

// MARK: - 关于

struct AboutSettingsView: View {
    @ObservedObject var store: LayoutStore
    @ObservedObject var controller: AppController

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LayoutSnap").font(.title2).bold()
                        Text("布局快照 · 窗口布局记忆与恢复 · 版本 \(version)")
                            .foregroundStyle(.secondary)
                        Text("基于 macOS Accessibility API 实现，不依赖私有接口。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("数据") {
                LabeledContent("布局数量") { Text("\(store.layouts.count)") }
                LabeledContent("数据目录") {
                    Text(store.directory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("日志文件") {
                    Text(Log.fileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("打开数据文件夹") {
                        NSWorkspace.shared.open(store.directory)
                    }
                    Button("打开日志") {
                        NSWorkspace.shared.selectFile(Log.fileURL.path, inFileViewerRootedAtPath: Log.directory.path)
                    }
                    Button("导出布局…") { exportLayouts() }
                    Button("导入布局…") { importLayouts() }
                }
            }

            Section("小提示") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 恢复时不会移动「当前处于全屏」的窗口，免得把你正在用的窗口踢出来。")
                    Text("• macOS 不允许第三方应用把窗口搬到别的「调度中心」空间，这一条 API 层面做不到。")
                    Text("• 窗口标题变了也能对得上，靠的是位置、尺寸和标题相似度综合打分。")
                    Text("• 换显示器/改分辨率后，窗口会按相对位置投影到新屏幕上。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func exportLayouts() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LayoutSnap-Layouts.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            controller.statusBar?.flash("布局已导出")
        } catch {
            controller.simpleAlert(title: "导出失败", message: error.localizedDescription)
        }
    }

    private func importLayouts() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.import(from: url)
            controller.statusBar?.flash("布局已导入")
        } catch {
            controller.simpleAlert(title: "导入失败", message: error.localizedDescription)
        }
    }
}
