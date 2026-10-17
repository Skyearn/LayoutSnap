import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let controller = AppController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        controller.statusBar = StatusBarController(controller: controller)
        controller.start()

        if !UserDefaults.standard.bool(forKey: "hasShownWelcome") {
            UserDefaults.standard.set(true, forKey: "hasShownWelcome")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.showWelcome()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.openSettings()
        return true
    }

    private func showWelcome() {
        let alert = NSAlert()
        alert.messageText = "欢迎使用 LayoutSnap（布局快照）"
        alert.informativeText = """
        LayoutSnap 帮你记住「现在这些窗口分别摆在哪里」，然后一键摆回去。

        用法：
        1. 点击菜单栏图标 › 保存当前布局，给当前这堆窗口起个名字
        2. 之后从菜单里点一下布局名（或按快捷键），窗口就会各回各位
        3. 换显示器、改分辨率也没关系，窗口会按比例投到新的屏幕上

        第一步需要授权：请到「系统设置 › 隐私与安全性 › 辅助功能」里勾选 LayoutSnap。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        if #available(macOS 13.0, *) {
            alert.addButton(withTitle: "顺便设置开机自启")
        }
        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        if #available(macOS 13.0, *), result == .alertSecondButtonReturn {
            AppSettings.shared.launchAtLogin = true
        }
        if !AX.isTrusted {
            controller.requestPermission()
        }
    }
}
