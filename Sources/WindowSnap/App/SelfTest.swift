import Foundation
import CoreGraphics
import AppKit

/// 不依赖辅助功能权限的自检：把最容易写错的几何换算和匹配算法跑一遍。
/// 用法：WindowSnap --selftest
enum SelfTest {

    private static var passed = 0
    private static var failed = 0
    private static var currentGroup = ""

    static func run() -> Int32 {
        group("显示器/窗口几何")

        let leftDisplay = CGRect(x: -2176, y: 0, width: 2176, height: 1224)
        let centerDisplay = CGRect(x: 0, y: 0, width: 2176, height: 1224)
        let smallerDisplay = CGRect(x: 2176, y: 0, width: 1728, height: 1117)

        // 归一化 -> 投影，同一块屏上必须一模一样
        let window = CGRect(x: -2076, y: 100, width: 1000, height: 800)
        let relative = Frame(window).relative(to: leftDisplay)
        check(approx(relative.x, (window.minX - leftDisplay.minX) / leftDisplay.width), "相对坐标 x")
        check(approx(relative.y, (window.minY - leftDisplay.minY) / leftDisplay.height), "相对坐标 y")
        check(approx(relative.width, window.width / leftDisplay.width), "相对坐标 width")

        let backAgain = relative.projected(onto: leftDisplay).cgRect
        check(rectEqual(backAgain, window), "归一化 -> 投影 往返一致")

        // 投影到尺寸完全不同的屏幕上，比例关系要保持
        let projected = relative.projected(onto: smallerDisplay).cgRect
        check(projected.minX > smallerDisplay.minX, "投影后落在目标屏内（x）")
        check(projected.maxX <= smallerDisplay.maxX + 0.001, "投影后不超出目标屏（x）")
        check(projected.maxY <= smallerDisplay.maxY + 0.001, "投影后不超出目标屏（y）")
        check(approx(projected.width / smallerDisplay.width, window.width / leftDisplay.width), "投影按比例缩放")

        // 屏幕变窄时的边界收缩
        group("越界收敛")

        let overflow = CGRect(x: -500, y: -200, width: 1200, height: 900)
        let clamped = ScreenGeometry.clampWithinVisibleArea(overflow, display: DisplayInfo(
            id: 1, index: 0, name: "test",
            frame: centerDisplay,
            visibleFrame: CGRect(x: 0, y: 25, width: 2176, height: 1174)))
        check(clamped.minX >= -8 && clamped.minY >= 25 - 8, "窗口左上角被拉回可见区域")
        check(clamped.maxX <= 2176 + 8 && clamped.maxY <= 1199 + 8, "窗口右下角被拉回可见区域")

        let tooBig = CGRect(x: 0, y: 0, width: 5000, height: 4000)
        let shrunk = ScreenGeometry.clampWithinVisibleArea(tooBig, display: DisplayInfo(
            id: 1, index: 0, name: "test",
            frame: centerDisplay,
            visibleFrame: CGRect(x: 0, y: 25, width: 2176, height: 1174)))
        check(shrunk.width <= 2176 + 16, "超宽窗口被压缩到屏幕宽度")

        // 显示器不在了 -> 投影到别的屏
        group("显示器丢失时的重投影")

        // 用一个现实中不可能存在的坐标，避免和这台机器真实的屏幕排列撞上
        let goneDisplay = CGRect(x: 100_000, y: 100_000, width: 1600, height: 1000)
        let goneWindow = CGRect(x: 100_100, y: 100_100, width: 900, height: 700)
        let snapshot = WindowSnapshot(
            bundleID: "com.test.app", appName: "Test", title: "窗口", role: "AXWindow", subrole: "AXStandardWindow",
            frame: Frame(goneWindow),
            displayID: 999999, displayIndex: 5, displayName: "已经拔掉的屏",
            displayFrame: Frame(goneDisplay),
            relativeFrame: Frame(goneWindow).relative(to: goneDisplay),
            isMinimized: false, isFullScreen: false, zIndex: 0)

        let resolved = ScreenGeometry.resolveTarget(for: snapshot)
        check(resolved.remapped, "显示器不存在时标记为重投影")
        check(resolved.frame.width > 0 && resolved.frame.height > 0, "重投影得到有效尺寸")

        // 原屏幕已经拔掉，落到哪块屏上都行，但必须实实在在落在某块现有屏幕上
        let currentScreens = ScreenGeometry.currentDisplays
        if currentScreens.isEmpty == false {
            let landed = currentScreens.contains { display in
                let intersection = resolved.frame.intersection(display.frame)
                return intersection.isNull == false && intersection.width > 0
            }
            check(landed, "重投影后落在当前某块屏幕上")
        }

        group("窗口匹配打分")

        check(WindowMatcher.titleSimilarity("活动监视器", "活动监视器") == 1.0, "标题完全相同得满分")
        check(WindowMatcher.titleSimilarity("项目 — 编辑", "项目 — 编辑") == 1.0, "标题完全相同得满分（带破折号）")
        check(WindowMatcher.titleSimilarity("", "") > 0, "两边都没标题也有基础分")
        check(WindowMatcher.titleSimilarity("Xcode", "") == 0, "一边没标题得零分")
        check(WindowMatcher.titleSimilarity("README.md - 项目", "README.md - 项目（已修改）") > 0.5, "包含关系得高分")
        check(WindowMatcher.titleSimilarity("Safari", "Terminal") < 0.3, "毫不相干得低分")
        check(WindowMatcher.normalizeTitle("  •   Hello   World  ") == "hello world", "标题归一化")
        check(WindowMatcher.normalizeTitle("● 未命名") == "● 未命名", "只去掉项目符号点")

        group("布局编解码")

        let layout = Layout(name: "自检布局", windows: [snapshot], hotKey: HotKeySpec.all.first,
                            triggerBundleIDs: ["com.apple.Safari"])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try encoder.encode([layout])
            let decoded = try decoder.decode([Layout].self, from: data)
            check(decoded.count == 1, "编码后能解回来")
            check(decoded.first?.name == "自检布局", "布局名字保持")
            check(decoded.first?.windows.count == 1, "窗口数量保持")
            check(decoded.first?.windows.first?.frame.width == snapshot.frame.width, "窗口尺寸保持")
            check(decoded.first?.relativeFrameStable ?? false, "相对坐标在序列化后保持不变")
        } catch {
            check(false, "布局编解码失败: \(error)")
        }

        group("快捷键")

        check(HotKeySpec.all.count == 27, "内置 27 组快捷键")
        check(HotKeySpec.all.first?.display == "⌃⌥1", "第一组是 ⌃⌥1")
        check(HotKeySpec.all.last?.display == "⌘⇧9", "最后一组是 ⌘⇧9")
        check(Set(HotKeySpec.all).count == HotKeySpec.all.count, "快捷键没有重复")

        group("布局存储")

        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("windowsnap-selftest.json")
        do {
            try LayoutStore.shared.export(to: temp)
            let data = try Data(contentsOf: temp)
            check(!data.isEmpty, "可以导出到文件")
            try? FileManager.default.removeItem(at: temp)
        } catch {
            check(false, "导出失败: \(error)")
        }
        check(!LayoutStore.shared.fileURL.path.isEmpty, "数据文件路径有效")

        group("布局编辑：单个窗口粒度")

        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("windowsnap-selftest-\(UUID().uuidString)", isDirectory: true)
        let tempStore = LayoutStore(directory: scratch)

        func makeSnapshot(_ title: String, bundle: String, app: String, x: Double) -> WindowSnapshot {
            var item = WindowSnapshot(
                bundleID: bundle, appName: app, title: title, role: "AXWindow", subrole: "AXStandardWindow",
                frame: Frame(x: x, y: 100, width: 600, height: 400),
                displayID: 1, displayIndex: 0, displayName: "测试屏",
                displayFrame: Frame(CGRect(x: 0, y: 0, width: 1440, height: 900)),
                relativeFrame: Frame(x: 0, y: 0, width: 1, height: 1),
                isMinimized: false, isFullScreen: false, zIndex: 0)
            item.syncDisplayInfo(displays: [DisplayInfo(id: 1, index: 0, name: "测试屏",
                                                        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                                        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875))])
            return item
        }

        let windowA = makeSnapshot("标签一", bundle: "com.test.browser", app: "测试浏览器", x: 100)
        let windowB = makeSnapshot("标签二", bundle: "com.test.browser", app: "测试浏览器", x: 300)
        let windowC = makeSnapshot("项目", bundle: "com.test.editor", app: "测试编辑器", x: 500)

        tempStore.add(name: "编辑测试", windows: [windowA, windowB, windowC])
        guard let editingID = tempStore.layouts.first?.id else {
            check(false, "创建测试布局失败")
            try? FileManager.default.removeItem(at: scratch)
            print("")
            print("通过 \(passed) 项，失败 \(failed) 项")
            return failed == 0 ? 0 : 1
        }

        check(tempStore.layout(id: editingID)?.windows.count == 3, "初始有 3 个窗口记录")
        check(tempStore.layout(id: editingID)?.windows.map(\.zIndex) == [0, 1, 2], "zIndex 从 0 开始连续编号")

        // 删掉单个窗口
        tempStore.removeWindows(ids: [windowB.id], from: editingID)
        check(tempStore.layout(id: editingID)?.windows.count == 2, "删掉一个窗口后剩 2 条")
        check(tempStore.layout(id: editingID)?.windows.contains { $0.id == windowB.id } == false,
              "被删的那条确实不在了")
        check(tempStore.layout(id: editingID)?.windows.map(\.zIndex) == [0, 1], "删除后 zIndex 重新连续编号")

        // 删掉一个应用的所有窗口
        let removedCount = tempStore.removeApp(bundleID: "com.test.browser", from: editingID)
        check(removedCount == 1, "删除应用返回被删掉的条数")
        check(tempStore.layout(id: editingID)?.windows.count == 1, "删掉应用后只剩另一个应用的窗口")
        check(tempStore.layout(id: editingID)?.windowsByApp.count == 1, "按应用分组也只剩一组")

        // 停用 / 启用
        tempStore.setWindowsEnabled(false, ids: [windowC.id], in: editingID)
        check(tempStore.layout(id: editingID)?.enabledWindows.count == 0, "停用之后不参与恢复")
        check(tempStore.layout(id: editingID)?.windows.count == 1, "停用不会删掉记录")
        tempStore.setWindowsEnabled(true, ids: [windowC.id], in: editingID)
        check(tempStore.layout(id: editingID)?.enabledWindows.count == 1, "重新启用后恢复参与")

        // 添加窗口（同一窗口重复添加应该覆盖而不是重复）
        tempStore.addWindows([windowA], to: editingID)
        check(tempStore.layout(id: editingID)?.windows.count == 2, "添加一个窗口")
        tempStore.addWindows([windowA], to: editingID)
        check(tempStore.layout(id: editingID)?.windows.count == 2, "重复添加同一个窗口不会变成两条")

        // 调整顺序
        guard let layoutAfterAdd = tempStore.layout(id: editingID),
              let firstID = layoutAfterAdd.windows.first?.id else {
            check(false, "读取顺序测试数据失败")
            try? FileManager.default.removeItem(at: scratch)
            return failed == 0 ? 0 : 1
        }
        let firstTitleBefore = layoutAfterAdd.windows[0].title
        tempStore.moveWindow(id: firstID, direction: 1, in: editingID)
        check(tempStore.layout(id: editingID)?.windows[1].title == firstTitleBefore, "上移/下移能改变顺序")
        check(tempStore.layout(id: editingID)?.windows.map(\.zIndex) == [0, 1], "调整顺序后重新编号")

        // 单窗口编辑：改坐标 + 匹配关键词
        guard var editTarget = tempStore.layout(id: editingID)?.windows.first else {
            check(false, "读取编辑目标失败")
            try? FileManager.default.removeItem(at: scratch)
            return failed == 0 ? 0 : 1
        }
        editTarget.frame = Frame(x: 2600, y: 300, width: 900, height: 700)
        editTarget.matchTitle = "固定关键词"
        editTarget.syncDisplayInfo(displays: [DisplayInfo(id: 7, index: 1, name: "第二屏",
                                                         frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                                                         visibleFrame: CGRect(x: 1440, y: 25, width: 1920, height: 1055))])
        tempStore.updateWindow(editTarget, in: editingID)
        let saved = tempStore.layout(id: editingID)?.windows.first { $0.id == editTarget.id }
        check(saved?.frame.x == 2600, "改完坐标存下来了")
        check(saved?.matchTitle == "固定关键词", "匹配关键词存下来了")
        check(saved?.displayID == 7, "换屏之后显示器 id 跟着更新")
        check(saved?.effectiveMatchTitle == "固定关键词", "有自定义关键词时优先用它匹配")
        check(saved?.relativeFrame.x ?? -1 > 0.55, "相对坐标按新显示器重算")

        // 覆盖保存：把整个布局的窗口换成另一批
        tempStore.replaceWindows([windowA, windowC], in: editingID)
        check(tempStore.layout(id: editingID)?.windows.count == 2, "「存进已有布局」会整个替换掉原来的窗口")
        check(tempStore.layout(id: editingID)?.windows.map(\.zIndex) == [0, 1], "替换之后重新编号 zIndex")
        check(tempStore.layout(id: editingID)?.windows.first?.bundleID == windowA.bundleID, "替换后的内容是新的那批窗口")

        // 「保存部分窗口」落到已有布局：整批替换
        tempStore.replaceWindows([windowB], in: editingID)
        check(tempStore.layout(id: editingID)?.windows.count == 1, "选中 1 个窗口替换掉整个布局")
        check(tempStore.layout(id: editingID)?.windows.first?.title == "标签二", "替换成的是挑中的那一个")

        // 「添加窗口」走的是追加，和上面不是一回事
        tempStore.addWindows([windowA], to: editingID)
        check(tempStore.layout(id: editingID)?.windows.count == 2, "追加窗口是在原有基础上加")

        // 落盘 / 再读回来
        tempStore.save()
        let reloaded = LayoutStore(directory: scratch)
        check(reloaded.layouts.count == 1, "编辑结果能写回文件并重新读出来")
        check(reloaded.layouts.first?.windows.count == tempStore.layouts.first?.windows.count,
              "重读之后窗口条数一致")
        try? FileManager.default.removeItem(at: scratch)

        group("老版本布局文件兼容")

        // 老文件里没有 relativeFrame / matchTitle / isEnabled，必须还能读出来
        let legacyJSON = """
        [{
          "id": "33333333-3333-3333-3333-333333333333",
          "name": "老版本布局",
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z",
          "triggerBundleIDs": [],
          "windows": [{
            "bundleID": "com.apple.Safari",
            "appName": "Safari",
            "title": "Apple",
            "role": "AXWindow",
            "subrole": "AXStandardWindow",
            "frame": { "x": 144, "y": 90, "width": 1152, "height": 720 },
            "displayID": 1,
            "displayIndex": 0,
            "displayName": "主屏",
            "displayFrame": { "x": 0, "y": 0, "width": 1440, "height": 900 },
            "isMinimized": false,
            "isFullScreen": false,
            "zIndex": 0
          }]
        }]
        """
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .iso8601
        if let data = legacyJSON.data(using: .utf8),
           let decoded = try? legacyDecoder.decode([Layout].self, from: data) {
            check(decoded.count == 1, "老文件整体能读出来")
            let window = decoded.first?.windows.first
            check(window?.bundleID == "com.apple.Safari", "窗口数据完整")
            check(window?.isEnabled == true, "缺 isEnabled 时默认是启用的")
            check(window?.matchTitle == nil, "缺 matchTitle 时是空")
            check(abs((window?.relativeFrame.x ?? 0) - 0.1) < 0.0001, "缺 relativeFrame 时按显示器算出来")
            check(window?.effectiveMatchTitle == "Apple", "没有自定义关键词时用窗口标题")
        } else {
            check(false, "老版本布局文件读不出来（兼容性坏了）")
        }

        group("显示器投影（单窗口编辑用得到）")

        var offScreen = makeSnapshot("跑出屏幕的窗口", bundle: "com.test.editor", app: "测试编辑器", x: 5000)
        offScreen.frame = Frame(x: 5000, y: 3000, width: 600, height: 400)
        offScreen.syncDisplayInfo()
        check(offScreen.displayName.isEmpty == false, "给一个离谱的坐标也能算出一块屏")

        let displaysForProjection = ScreenGeometry.currentDisplays
        if let firstDisplay = displaysForProjection.first {
            var projected = offScreen
            projected.frame = projected.relativeFrame.projected(onto: firstDisplay.frame)
            let clamped = ScreenGeometry.clampWithinVisibleArea(projected.frame.cgRect, display: firstDisplay)
            let intersection = clamped.intersection(firstDisplay.frame)
            check(intersection.isNull == false && intersection.width > 0, "投影回来之后落在屏幕里")
        }

        group("忽略的应用选择器")

        let suiteName = "com.windowsnap.selftest"
        let testDefaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        testDefaults.removePersistentDomain(forName: suiteName)
        let testSettings = AppSettings(defaults: testDefaults)

        testSettings.addExcludedApp("com.apple.finder")
        testSettings.addExcludedApp("com.apple.Safari")
        testSettings.addExcludedApp("com.apple.finder")
        check(testSettings.excludedAppList.count == 2, "重复添加同一个应用不会出现两条")
        check(testSettings.excludedAppList.first == "com.apple.finder", "保持添加顺序")
        check(testSettings.excludedBundleIDs.contains("com.apple.Safari"), "忽略集合里包含刚加的应用")

        testSettings.removeExcludedApp("com.apple.finder")
        check(testSettings.excludedAppList == ["com.apple.Safari"], "删除只删掉指定的那一个")

        testSettings.toggleExcludedApp("com.apple.Terminal")
        check(testSettings.excludedBundleIDs.contains("com.apple.Terminal"), "toggle 能加进来")
        testSettings.toggleExcludedApp("com.apple.Terminal")
        check(testSettings.excludedBundleIDs.contains("com.apple.Terminal") == false, "toggle 能删掉")

        // 老版本手输的混合分隔符格式也要能解析
        testSettings.excludedBundleIDsText = "com.a.app, com.b.app\ncom.c.app;com.d.app  com.e.app"
        check(testSettings.excludedAppList.count == 5, "手写的逗号/换行/分号/空格混合分隔符都能解析")
        check(testSettings.excludedAppList.contains("com.e.app"), "空格分隔的也能识别")
        testDefaults.removePersistentDomain(forName: suiteName)

        group("快捷键与全局动作")

        check(HotKeySpec.defaultRestore.display == "⌃Z", "恢复布局的默认快捷键是 ⌃Z")
        check(HotKeySpec.defaultRestore.keyCode == KeyCodeMap.z, "默认快捷键的键码是 Z")
        check(HotKeySpec.defaultRestore.carbonModifiers == HotKeySpec.control, "默认快捷键带 ⌃")
        check(HotKeySpec.defaultRestore.keyEquivalent == "z", "默认快捷键能在菜单里显示成 z")

        check(AppAction.allCases.count == 4, "一共四个全局动作")
        let withDefault = AppAction.allCases.filter { $0.defaultHotKey != nil }
        check(withDefault.count == 1, "只有「恢复布局」有默认快捷键")
        check(withDefault.first == .restoreLayout, "带默认键的是恢复布局")
        check(AppAction.saveAllWindows.defaultHotKey == nil, "保存所有窗口默认不设快捷键")
        check(AppAction.savePartialWindows.defaultHotKey == nil, "保存部分窗口默认不设快捷键")
        check(AppAction.saveCurrentWindow.defaultHotKey == nil, "保存当前窗口默认不设快捷键")

        let allFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let carbon = HotKeyKeys.carbonModifiers(from: allFlags)
        check(carbon == HotKeySpec.control | HotKeySpec.option | HotKeySpec.shift | HotKeySpec.command,
              "修饰键换算成 Carbon 掩码")
        check(HotKeyKeys.modifierFlags(from: carbon) == allFlags, "再换算回 NSEvent 掩码一致")
        check(HotKeyKeys.carbonModifiers(from: []) == 0, "没有修饰键时掩码为 0")
        check(HotKeySpec(keyCode: 6, carbonModifiers: HotKeySpec.command, display: "⌘Z")
                .conflicts(with: HotKeySpec(keyCode: 6, carbonModifiers: HotKeySpec.command, display: "别的名字")),
              "同一组合键能识别出冲突")
        check(HotKeySpec(keyCode: 6, carbonModifiers: HotKeySpec.command, display: "⌘Z")
                .conflicts(with: HotKeySpec(keyCode: 6, carbonModifiers: HotKeySpec.control, display: "⌃Z")) == false,
              "不同修饰键不算冲突")

        check(HotKeyKeys.keyDisplay(keyCode: 36, characters: nil) == "↩", "回车显示成 ↩")
        check(HotKeyKeys.keyDisplay(keyCode: 123, characters: nil) == "←", "方向键显示成箭头")
        check(HotKeyKeys.keyDisplay(keyCode: 6, characters: "z") == "Z", "字母键显示成大写")
        check(KeyCodeMap.menuKeyEquivalent(36) == "\r", "回车在菜单里的等价键正确")
        check(KeyCodeMap.modifierDisplay(HotKeySpec.control | HotKeySpec.command) == "⌃⌘", "修饰键显示顺序")

        let actionSuite = "com.windowsnap.selftest.actions"
        let actionDefaults = UserDefaults(suiteName: actionSuite) ?? UserDefaults.standard
        actionDefaults.removePersistentDomain(forName: actionSuite)
        let actionSettings = AppSettings(defaults: actionDefaults)
        check(actionSettings.hotKey(for: .restoreLayout)?.display == "⌃Z", "新安装默认给恢复布局 ⌃Z")
        check(actionSettings.hotKey(for: .saveAllWindows) == nil, "新安装不给保存动作配快捷键")

        actionSettings.setHotKey(HotKeySpec.all[3], for: .saveAllWindows)
        check(actionSettings.hotKey(for: .saveAllWindows)?.display == HotKeySpec.all[3].display, "能设置动作快捷键")
        check(actionDefaults.data(forKey: "actionHotKeys") != nil, "动作快捷键写进了 UserDefaults")
        let reloadedSettings = AppSettings(defaults: actionDefaults)
        check(reloadedSettings.hotKey(for: .saveAllWindows)?.display == HotKeySpec.all[3].display,
              "重启之后动作快捷键还在")

        actionSettings.setHotKey(nil, for: .restoreLayout)
        check(actionSettings.hotKey(for: .restoreLayout) == nil, "能清除默认快捷键")
        let clearedSettings = AppSettings(defaults: actionDefaults)
        check(clearedSettings.hotKey(for: .restoreLayout) == nil, "清除之后不会被默认值顶回来")
        actionDefaults.removePersistentDomain(forName: actionSuite)

        group("并行与缓存")

        let scanDefaults = ScanOptions()
        check(scanDefaults.maxConcurrentApps == 4, "扫描默认并行处理 4 个应用")

        let restoreDefaults = WindowRestorer.Options()
        check(restoreDefaults.maxConcurrentApps == 4, "恢复默认并行处理 4 个应用")

        let cacheFirst = ScreenGeometry.currentDisplays
        let cacheSecond = ScreenGeometry.currentDisplays
        check(cacheFirst.count == cacheSecond.count, "显示器列表走缓存，两次结果一致")
        ScreenGeometry.invalidateDisplayCache()
        let cacheThird = ScreenGeometry.currentDisplays
        check(cacheThird.count == cacheFirst.count, "清掉缓存后重新查询结果一致")

        let perfSuite = "com.windowsnap.selftest.perf"
        let perfDefaults = UserDefaults(suiteName: perfSuite) ?? UserDefaults.standard
        perfDefaults.removePersistentDomain(forName: perfSuite)
        let perfSettings = AppSettings(defaults: perfDefaults)
        check(perfSettings.parallelWorkers == 4, "并行数默认 4")
        perfSettings.parallelWorkers = 8
        check(AppSettings(defaults: perfDefaults).parallelWorkers == 8, "并行数改动会持久化")
        check(perfSettings.restorerOptions.maxConcurrentApps == 8, "恢复选项跟着设置走")
        perfDefaults.removePersistentDomain(forName: perfSuite)

        group("显示器识别（重启后 displayID 会变）")

        // 模拟：显示器排列没变，但重启后 id 被重新分配了
        let mainScreen = DisplayInfo(id: 1, uuid: "UUID-MAIN", index: 0, name: "F27G60U",
                                     frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                     visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055))
        let leftScreen = DisplayInfo(id: 2, uuid: "UUID-LEFT", index: 1, name: "TYPE-C",
                                     frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                                     visibleFrame: CGRect(x: -1920, y: 25, width: 1920, height: 1055))
        let testScreens = [mainScreen, leftScreen]

        // 保存时这个窗口在主屏上，当时主屏的 id 是 9
        let savedFrame = CGRect(x: 0, y: 30, width: 1920, height: 1050)
        let savedDisplayFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var savedWindow = WindowSnapshot(
            bundleID: "com.apple.Safari", appName: "Safari", title: "个人",
            role: "AXWindow", subrole: "AXStandardWindow",
            frame: Frame(savedFrame),
            displayID: 9,
            displayUUID: "UUID-MAIN",
            displayIndex: 0,
            displayName: "F27G60U",
            displayFrame: Frame(savedDisplayFrame),
            relativeFrame: Frame(savedFrame).relative(to: savedDisplayFrame),
            isMinimized: false, isFullScreen: false, zIndex: 0)

        // 这是用户报的那个 bug：重启后 id=2 被左边那块屏占用了，
        // 老逻辑按 id 找屏，会把窗口甩到 TYPE-C 上
        savedWindow.displayID = 2
        let bugMatched = ScreenGeometry.matchDisplay(for: savedWindow, in: testScreens)
        check(bugMatched?.uuid == "UUID-MAIN", "displayID 被别的屏占用时，按 UUID 找到原来那块屏")
        check(bugMatched?.name == "F27G60U", "匹配到的是主屏，而不是 TYPE-C")

        let bugResolved = ScreenGeometry.resolveTarget(for: savedWindow, in: testScreens)
        check(bugResolved.display.uuid == "UUID-MAIN", "恢复目标锁定在主屏")
        check(bugResolved.remapped == false, "屏幕没挪窝时用绝对坐标，不做重投影")
        check(rectEqual(bugResolved.frame, savedFrame), "位置尺寸原样还原")

        // 屏幕整体挪到别的坐标（排列变了）-> 应该按相对坐标投影
        let movedMain = DisplayInfo(id: 1, uuid: "UUID-MAIN", index: 0, name: "F27G60U",
                                    frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                                    visibleFrame: CGRect(x: 1920, y: 25, width: 1920, height: 1055))
        let movedResolved = ScreenGeometry.resolveTarget(for: savedWindow, in: [movedMain, leftScreen])
        check(movedResolved.remapped, "屏幕位置变了会标记为重投影")
        check(movedResolved.frame.minX >= 1920 - 8, "重投影之后落在屏幕的新位置上")

        // 老数据没有 UUID：靠「屏幕矩形一模一样」也能认出来
        var legacy = savedWindow
        legacy.displayUUID = nil
        legacy.displayID = 99
        let legacyMatched = ScreenGeometry.matchDisplay(for: legacy, in: testScreens)
        check(legacyMatched?.uuid == "UUID-MAIN", "没有 UUID 的老数据按屏幕矩形匹配")

        // 换成一台全新的显示器：老的 UUID 和矩形都对不上，退到按序号
        var brandNew = savedWindow
        brandNew.displayUUID = "UUID-OTHER"
        brandNew.displayID = 77
        let fallback = ScreenGeometry.matchDisplay(for: brandNew, in: testScreens)
        check(fallback?.index == brandNew.displayIndex, "认不出显示器时按保存时的屏幕序号退化")

        group("显示器缓存的失效")

        let cachedBefore = ScreenGeometry.currentDisplays.count
        ScreenGeometry.invalidateDisplayCache()
        check(ScreenGeometry.currentDisplays.count == cachedBefore, "清缓存后重新查询显示器数量一致")
        check(ScreenGeometry.persistentUUID(of: CGMainDisplayID()).isEmpty == false,
              "主屏能取到稳定的 EDID UUID")

        print("")
        print("通过 \(passed) 项，失败 \(failed) 项")
        if failed == 0 {
            print("✅ 全部通过")
        } else {
            print("❌ 有 \(failed) 项没过")
        }
        return failed == 0 ? 0 : 1
    }

    // MARK: - 断言工具

    private static func group(_ name: String) {
        currentGroup = name
        print("\n[\(name)]")
    }

    private static func check(_ condition: Bool, _ name: String) {
        if condition {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            print("  ✗ \(name)   ← 失败了")
        }
    }

    private static func approx(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private static func rectEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.01) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}

private extension Layout {
    /// 相对坐标经过 encode/decode 之后是否还等价
    var relativeFrameStable: Bool {
        guard let window = windows.first else { return false }
        let recomputed = window.frame.relative(to: window.displayFrame.cgRect)
        return abs(recomputed.x - window.relativeFrame.x) < 0.0001
            && abs(recomputed.width - window.relativeFrame.width) < 0.0001
    }
}
