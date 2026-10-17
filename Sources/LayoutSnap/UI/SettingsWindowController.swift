import AppKit
import SwiftUI
import Combine

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case layouts
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .layouts: return "布局"
        case .shortcuts: return "快捷键"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .layouts: return "rectangle.3.group"
        case .shortcuts: return "command"
        case .about: return "info.circle"
        }
    }
}

final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
    /// 从菜单栏「编辑布局…」跳进来时，直接选中这个布局
    @Published var selectedLayoutID: UUID?
}

/// 设置窗口（SwiftUI 内容，外面套个 NSWindow）
final class SettingsWindowController: NSWindowController {

    private let navigation = SettingsNavigation()

    init(store: LayoutStore, settings: AppSettings, controller: AppController) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "布局快照 设置"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 480)
        window.center()

        super.init(window: window)

        let root = SettingsView(store: store,
                                settings: settings,
                                controller: controller,
                                navigation: navigation)
            .environmentObject(controller)

        // 用一个容器 + 约束装 SwiftUI 视图，避免窗口缩放时内容不跟着走
        let container = NSView()
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        window.contentView = container
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(tab: SettingsTab, layoutID: UUID? = nil) {
        navigation.tab = tab
        if let layoutID {
            navigation.selectedLayoutID = layoutID
        }
        if AppSettings.shared.launchAtLogin {
            AppSettings.shared.applyLaunchAtLogin()
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
