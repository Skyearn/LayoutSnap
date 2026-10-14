import Foundation
import CoreGraphics

/// 可编码的矩形。CGRect 在不同平台/工具链下的 Codable 表现不一致，
/// 自己存一份，JSON 也更易读、可手工编辑。
struct Frame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(x: Double(rect.origin.x), y: Double(rect.origin.y),
                  width: Double(rect.width), height: Double(rect.height))
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var isUsableWindowFrame: Bool {
        width >= 80 && height >= 60 && width.isFinite && height.isFinite
    }

    /// 相对某个显示器（Quartz 全局坐标，左上原点）的归一化坐标
    func relative(to display: CGRect) -> Frame {
        guard display.width > 0, display.height > 0 else { return Frame(x: 0, y: 0, width: 1, height: 1) }
        return Frame(x: (x - Double(display.minX)) / Double(display.width),
                     y: (y - Double(display.minY)) / Double(display.height),
                     width: width / Double(display.width),
                     height: height / Double(display.height))
    }

    /// 把归一化坐标投影回真实显示器
    func projected(onto display: CGRect) -> Frame {
        Frame(x: Double(display.minX) + x * Double(display.width),
              y: Double(display.minY) + y * Double(display.height),
              width: width * Double(display.width),
              height: height * Double(display.height))
    }
}

/// 一个窗口的完整快照
struct WindowSnapshot: Codable, Identifiable, Hashable {
    var id: UUID

    var bundleID: String
    var appName: String
    var title: String
    var role: String
    var subrole: String

    /// 保存时的全局坐标（Quartz：左上角原点）
    var frame: Frame

    var displayID: UInt32
    /// 显示器稳定标识（EDID UUID）。displayID 重启后会重新分配，只能靠这个认屏。
    var displayUUID: String?
    var displayIndex: Int
    var displayName: String
    /// 保存时该显示器的全局矩形
    var displayFrame: Frame
    /// 相对显示器的归一化矩形（换屏/改分辨率时的救命稻草）
    var relativeFrame: Frame

    var isMinimized: Bool
    var isFullScreen: Bool
    /// 前后顺序，0 在最前面
    var zIndex: Int

    /// 自定义匹配关键词。窗口标题会变（浏览器标签、正在编辑的文档），
    /// 这里填一段固定关键词，恢复时就优先拿它去认窗口。
    var matchTitle: String?

    /// 关掉之后这条记录保留，但不参与恢复
    var isEnabled: Bool

    init(bundleID: String,
         appName: String,
         title: String,
         role: String,
         subrole: String,
         frame: Frame,
         displayID: UInt32,
         displayUUID: String? = nil,
         displayIndex: Int,
         displayName: String,
         displayFrame: Frame,
         relativeFrame: Frame,
         isMinimized: Bool,
         isFullScreen: Bool,
         zIndex: Int,
         matchTitle: String? = nil,
         isEnabled: Bool = true,
         id: UUID = UUID()) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.displayID = displayID
        self.displayUUID = displayUUID
        self.displayIndex = displayIndex
        self.displayName = displayName
        self.displayFrame = displayFrame
        self.relativeFrame = relativeFrame
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.zIndex = zIndex
        self.matchTitle = matchTitle
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id, bundleID, appName, title, role, subrole
        case frame, displayID, displayUUID, displayIndex, displayName, displayFrame, relativeFrame
        case isMinimized, isFullScreen, zIndex, matchTitle, isEnabled
    }

    /// 手写解码：老版本存的文件里没有 matchTitle / isEnabled / relativeFrame，
    /// 缺字段不能导致整份布局读不出来。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleID = try container.decode(String.self, forKey: .bundleID)
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? bundleID
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "AXWindow"
        subrole = try container.decodeIfPresent(String.self, forKey: .subrole) ?? ""
        frame = try container.decode(Frame.self, forKey: .frame)
        displayID = try container.decodeIfPresent(UInt32.self, forKey: .displayID) ?? 0
        displayUUID = try container.decodeIfPresent(String.self, forKey: .displayUUID)
        displayIndex = try container.decodeIfPresent(Int.self, forKey: .displayIndex) ?? 0
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        displayFrame = try container.decodeIfPresent(Frame.self, forKey: .displayFrame) ?? frame
        relativeFrame = try container.decodeIfPresent(Frame.self, forKey: .relativeFrame)
            ?? frame.relative(to: displayFrame.cgRect)
        isMinimized = try container.decodeIfPresent(Bool.self, forKey: .isMinimized) ?? false
        isFullScreen = try container.decodeIfPresent(Bool.self, forKey: .isFullScreen) ?? false
        zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        matchTitle = try container.decodeIfPresent(String.self, forKey: .matchTitle)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    /// 列表里显示的名字
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    /// 恢复时真正拿去匹配的文本
    var effectiveMatchTitle: String {
        if let matchTitle, matchTitle.isEmpty == false {
            return matchTitle
        }
        return title
    }

    var frameDescription: String {
        "\(Int(frame.width))×\(Int(frame.height)) @ (\(Int(frame.x)), \(Int(frame.y)))"
    }

    var subtitle: String {
        var parts: [String] = ["\(appName) · \(frameDescription)"]
        if displayName.isEmpty == false { parts.append(displayName) }
        if isMinimized { parts.append("已最小化") }
        if isFullScreen { parts.append("全屏") }
        if isEnabled == false { parts.append("已停用") }
        return parts.joined(separator: " · ")
    }

    /// 位置尺寸改了之后，重新算一遍「在哪块屏上」和相对坐标
    mutating func syncDisplayInfo(displays: [DisplayInfo] = ScreenGeometry.currentDisplays) {
        guard let display = ScreenGeometry.display(containing: frame.cgRect, in: displays) else { return }
        displayID = display.id
        displayUUID = display.uuid
        displayIndex = display.index
        displayName = display.name
        displayFrame = Frame(display.frame)
        relativeFrame = frame.relative(to: display.frame)
    }
}

/// 一组快捷键
struct HotKeySpec: Codable, Hashable {
    /// Carbon 虚拟键码（和 NSEvent.keyCode 是同一套）
    var keyCode: UInt32
    /// Carbon 修饰键（cmdKey / shiftKey / optionKey / controlKey）
    var carbonModifiers: UInt32
    /// 显示用文案，例如 "⌃⌥1"
    var display: String
    /// 菜单里那行右侧的快捷键字符（只是显示用，可以没有）
    var keyEquivalent: String? = nil

    static let all: [HotKeySpec] = {
        var result: [HotKeySpec] = []
        let sets: [(String, UInt32)] = [
            ("⌃⌥", HotKeySpec.control | HotKeySpec.option),
            ("⌃⇧", HotKeySpec.control | HotKeySpec.shift),
            ("⌘⇧", HotKeySpec.command | HotKeySpec.shift)
        ]
        for (prefix, mods) in sets {
            for digit in 1...9 {
                guard let code = KeyCodeMap.digitKeyCodes[digit] else { continue }
                result.append(HotKeySpec(keyCode: code,
                                         carbonModifiers: mods,
                                         display: prefix + "\(digit)",
                                         keyEquivalent: "\(digit)"))
            }
        }
        return result
    }()

    static let command: UInt32 = 0x0100
    static let shift: UInt32 = 0x0200
    static let option: UInt32 = 0x0800
    static let control: UInt32 = 0x1000

    /// 唯一默认设置的热键：⌃Z，给「恢复布局」用
    static let defaultRestore = HotKeySpec(keyCode: KeyCodeMap.z,
                                           carbonModifiers: HotKeySpec.control,
                                           display: "⌃Z",
                                           keyEquivalent: "z")

    var isEmpty: Bool { display.isEmpty }

    /// 是否和另一个快捷键冲突
    func conflicts(with other: HotKeySpec) -> Bool {
        keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
    }
}

/// 一个布局
struct Layout: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var windows: [WindowSnapshot] = []
    /// 一键恢复用的全局快捷键
    var hotKey: HotKeySpec?
    /// 这些应用启动时自动恢复本布局
    var triggerBundleIDs: [String] = []

    /// 只保留启用的窗口
    var enabledWindows: [WindowSnapshot] {
        windows.filter { $0.isEnabled }
    }

    var appSummary: String {
        var seen: [String] = []
        for window in windows where seen.contains(window.appName) == false {
            seen.append(window.appName)
        }
        let head = seen.prefix(3).joined(separator: "、")
        if seen.count > 3 { return head + " 等 \(seen.count) 个应用" }
        return head
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名布局" : trimmed
    }

    /// 按应用分组，保持布局里的前后顺序
    var windowsByApp: [(bundleID: String, appName: String, windows: [WindowSnapshot])] {
        var order: [String] = []
        var buckets: [String: [WindowSnapshot]] = [:]
        for window in windows {
            if buckets[window.bundleID] == nil {
                order.append(window.bundleID)
                buckets[window.bundleID] = []
            }
            buckets[window.bundleID]?.append(window)
        }
        return order.compactMap { bundleID in
            guard let items = buckets[bundleID], let first = items.first else { return nil }
            return (bundleID: bundleID, appName: first.appName, windows: items)
        }
    }
}

/// 恢复结果
struct RestoreReport {
    var restored = 0
    var skipped = 0
    var failed = 0
    var notes: [String] = []

    var summary: String {
        var parts: [String] = []
        parts.append("已恢复 \(restored) 个窗口")
        if skipped > 0 { parts.append("跳过 \(skipped) 个") }
        if failed > 0 { parts.append("失败 \(failed) 个") }
        return parts.joined(separator: "，")
    }
}
