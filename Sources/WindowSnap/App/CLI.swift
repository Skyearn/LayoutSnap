import Foundation
import AppKit

/// 命令行模式：不开界面，直接把能力暴露出来，方便调试和脚本化。
///
///   WindowSnap --doctor              检查权限 / 显示器 / 布局
///   WindowSnap --scan                打印当前窗口列表
///   WindowSnap --scan --json         以 JSON 输出
///   WindowSnap --save "工作"          把当前窗口存成布局
///   WindowSnap --restore "工作"       恢复布局
///   WindowSnap --list                列出所有布局
enum CLI {

    static func handle(arguments: [String]) -> Bool {
        let args = Array(arguments.dropFirst())
        guard let command = args.first else { return false }

        switch command {
        case "--help", "-h", "help":
            printHelp()
            return true
        case "--doctor":
            doctor()
            return true
        case "--scan":
            scan(json: args.contains("--json"))
            return true
        case "--list":
            list()
            return true
        case "--check-layout":
            guard args.count >= 2 else { fail("用法：WindowSnap --check-layout \"布局名字\"") }
            checkLayout(name: args[1])
            return true
        case "--selftest":
            exit(SelfTest.run())
        case "--save":
            guard args.count >= 2 else { fail("用法：WindowSnap --save \"布局名字\"") }
            save(name: args[1])
            return true
        case "--restore":
            guard args.count >= 2 else { fail("用法：WindowSnap --restore \"布局名字\"") }
            restore(name: args[1])
            return true
        case "--save-window":
            guard args.count >= 2, let index = Int(args[1]) else {
                fail("用法：WindowSnap --save-window 序号 [布局名字]")
            }
            saveWindow(index: index, name: args.count >= 3 ? args[2] : nil)
            return true
        default:
            return false
        }
    }

    // MARK: - 命令

    private static func printHelp() {
        print("""
        WindowSnap - 窗口布局记忆工具（菜单栏应用）

        直接运行（不带参数）会启动菜单栏图标。

        命令行模式：
          --doctor              检查辅助功能权限、显示器、已保存布局
          --scan [--json]       打印当前所有窗口
          --save "名字"          把当前窗口保存成布局
          --save-window 3 "名字" 只把扫描列表里第 3 个窗口存成布局
          --restore "名字"       恢复指定布局
          --list                列出已保存的布局
          --check-layout "名字"  只计算恢复目标落在哪块屏上，不移动窗口
          --help                显示本帮助

        数据目录：\(LayoutStore.shared.directory.path)
        """)
    }

    private static func doctor() {
        print("WindowSnap 自检")
        print("  辅助功能权限：\(AX.isTrusted ? "已获得 ✅" : "未获得 ❌")")
        if !AX.isTrusted {
            print("     → 系统设置 › 隐私与安全性 › 辅助功能，勾选运行本程序的 App（终端 / WindowSnap）")
        }

        let displays = ScreenGeometry.currentDisplays
        print("  显示器：\(displays.count) 块")
        for display in displays {
            print("    #\(display.index) \(display.name) id=\(display.id) "
                  + "位置=(\(Int(display.frame.minX)),\(Int(display.frame.minY))) "
                  + "尺寸=\(Int(display.frame.width))x\(Int(display.frame.height))")
        }

        print("  功能快捷键：")
        for action in AppAction.allCases {
            let spec = AppSettings.shared.hotKey(for: action)
            print("    - \(action.title)：\(spec?.display ?? "未设置")")
        }

        let store = LayoutStore.shared
        print("  布局：\(store.layouts.count) 个")
        for layout in store.layouts {
            let hotKey = layout.hotKey?.display ?? "无"
            print("    - \(layout.displayName)：\(layout.windows.count) 个窗口，快捷键 \(hotKey)")
        }
        print("  数据文件：\(store.fileURL.path)")
        print("  日志文件：\(Log.fileURL.path)")
    }

    private static func scan(json: Bool) {
        guard AX.isTrusted else {
            fail("没有辅助功能权限，扫描结果会是空的。请先授权。")
        }
        let snapshots = WindowScanner.snapshot()
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshots), let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }

        print("共 \(snapshots.count) 个窗口")
        for (index, snapshot) in snapshots.enumerated() {
            let frame = snapshot.frame
            let title = snapshot.title.isEmpty ? "(无标题)" : snapshot.title
            print(String(format: "%2d. [%@] %@ | %@ | %.0fx%.0f @ (%.0f,%.0f) | %@",
                         index + 1,
                         snapshot.appName,
                         title,
                         snapshot.subrole.isEmpty ? snapshot.role : snapshot.subrole,
                         frame.width, frame.height, frame.x, frame.y,
                         snapshot.displayName))
        }
    }

    /// 不移动任何窗口，只算一遍「每条记录现在会被放到哪块屏幕上」。
    /// 用来排查「窗口跑到别的显示器」这类问题。
    private static func checkLayout(name: String) {
        let store = LayoutStore.shared
        guard let layout = store.layouts.first(where: { $0.name == name })
                ?? store.layouts.first(where: { $0.id.uuidString.lowercased().hasPrefix(name.lowercased()) }) else {
            fail("找不到布局「\(name)」，用 --list 看看有哪些")
        }

        let displays = ScreenGeometry.currentDisplays
        print("布局「\(layout.displayName)」共 \(layout.windows.count) 个窗口")
        print("当前显示器：" + displays.map { "\($0.name)(id=\($0.id))" }.joined(separator: "、"))
        print("")

        var mismatched = 0
        for window in layout.windows {
            let resolved = ScreenGeometry.resolveTarget(for: window, in: displays)
            if resolved.display.name != window.displayName { mismatched += 1 }
            let mark = resolved.display.name == window.displayName ? "  " : "->"
            print("\(mark) [\(window.appName)] \(window.displayTitle)")
            print("     保存时：\(window.displayName)  \(Int(window.frame.x)),\(Int(window.frame.y)) \(Int(window.frame.width))x\(Int(window.frame.height))")
            print("     现在会：\(resolved.display.name)  \(Int(resolved.frame.origin.x)),\(Int(resolved.frame.origin.y)) \(Int(resolved.frame.width))x\(Int(resolved.frame.height))\(resolved.remapped ? "（按相对坐标重投影）" : "")")
        }

        print("")
        if mismatched == 0 {
            print("全部窗口都会回到保存时的那块屏幕")
        } else {
            print("有 \(mismatched) 个窗口会被放到与保存时不同的屏幕上（显示器换了，或识别失败）")
        }
    }

    private static func list() {
        let layouts = LayoutStore.shared.layouts
        if layouts.isEmpty {
            print("还没有保存过布局")
            return
        }
        for layout in layouts {
            print("\(layout.displayName)  (\(layout.windows.count) 个窗口, 快捷键 \(layout.hotKey?.display ?? "无"))")
            for snapshot in layout.windows {
                let frame = snapshot.frame
                print("    - [\(snapshot.appName)] \(snapshot.title.isEmpty ? "(无标题)" : snapshot.title) "
                      + "\(Int(frame.width))x\(Int(frame.height)) @ (\(Int(frame.x)),\(Int(frame.y)))")
            }
        }
    }

    private static func save(name: String) {
        guard AX.isTrusted else {
            fail("没有辅助功能权限，无法扫描窗口。")
        }
        let snapshots = WindowScanner.snapshot()
        guard !snapshots.isEmpty else {
            fail("没有扫描到任何窗口")
        }
        let layout = LayoutStore.shared.add(name: name, windows: snapshots)
        print("已保存布局「\(layout.displayName)」，包含 \(snapshots.count) 个窗口")
    }

    /// 只保存一个窗口：序号就是 --scan 输出的那个编号
    private static func saveWindow(index: Int, name: String?) {
        guard AX.isTrusted else {
            fail("没有辅助功能权限，无法扫描窗口。")
        }
        let snapshots = WindowScanner.snapshot()
        guard index >= 1, index <= snapshots.count else {
            fail("序号超出范围。先跑 --scan，序号是 1 到 \(snapshots.count)")
        }
        let snapshot = snapshots[index - 1]
        let layout = LayoutStore.shared.add(name: name ?? snapshot.displayTitle, windows: [snapshot])
        print("已保存单个窗口：布局「\(layout.displayName)」← [\(snapshot.appName)] \(snapshot.displayTitle)")
    }

    private static func restore(name: String) {
        guard AX.isTrusted else {
            fail("没有辅助功能权限，无法恢复窗口。")
        }
        let store = LayoutStore.shared
        guard let layout = store.layouts.first(where: { $0.name == name })
                ?? store.layouts.first(where: { $0.id.uuidString.lowercased().hasPrefix(name.lowercased()) }) else {
            fail("找不到布局「\(name)」，用 --list 看看有哪些")
        }

        var finished = false
        let restorer = WindowRestorer()
        restorer.restore(layout: layout,
                         options: AppSettings.shared.restorerOptions,
                         progress: { print("  … \($0)") },
                         completion: { report in
                             print(report.summary)
                             for note in report.notes { print("  备注：\(note)") }
                             finished = true
                         })

        let deadline = Date().addingTimeInterval(120)
        while !finished && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if !finished { fail("恢复超时") }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
        exit(1)
    }
}
