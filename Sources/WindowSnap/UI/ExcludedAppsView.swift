import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 「忽略的应用」选择器：直接从应用列表里点选，不用手输 Bundle ID
struct ExcludedAppsView: View {

    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AppController

    @State private var runningApps: [(bundleID: String, name: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("这些应用的窗口不会被扫描，也不会被恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                addMenu
            }

            if settings.excludedAppList.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text("还没有忽略任何应用")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(settings.excludedAppList, id: \.self) { bundleID in
                    appRow(bundleID)
                }
            }
        }
        .onAppear { refreshRunningApps() }
    }

    private var addMenu: some View {
        Menu {
            if runningApps.isEmpty {
                Text("没有正在运行的应用")
            }
            ForEach(runningApps, id: \.bundleID) { app in
                Button {
                    settings.addExcludedApp(app.bundleID)
                    refreshRunningApps()
                } label: {
                    Text(app.name)
                }
            }
            Divider()
            Button("刷新列表") { refreshRunningApps() }
            Button("从「应用程序」里选择…") { chooseFromDisk() }
        } label: {
            Label("添加应用…", systemImage: "plus")
        }
        .frame(width: 130)
    }

    private func appRow(_ bundleID: String) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: IconCache.icon(for: bundleID))
                .resizable()
                .frame(width: 16, height: 16)
            Text(AppLauncher.appName(for: bundleID))
            Text(bundleID)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                settings.removeExcludedApp(bundleID)
                refreshRunningApps()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private func refreshRunningApps() {
        runningApps = AppLauncher.installedRegularApplications()
            .filter { settings.excludedBundleIDs.contains($0.bundleID) == false }
    }

    private func chooseFromDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "忽略"
        panel.message = "选择要忽略的应用（可以多选）"

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            settings.addExcludedApp(bundleID)
        }
    }
}
