import AppKit

// 纯 AppKit 启动：这是个菜单栏小工具，没有主窗口，也不需要 SwiftUI 的 App 生命周期
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// 命令行模式（--scan / --restore 等）先处理掉，处理完直接退出，不进主循环
if CLI.handle(arguments: CommandLine.arguments) {
    exit(0)
}

let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
