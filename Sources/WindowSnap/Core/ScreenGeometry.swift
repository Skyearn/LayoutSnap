import AppKit
import CoreGraphics

/// 一块显示器的信息
struct DisplayInfo: Hashable {
    var id: CGDirectDisplayID
    /// 显示器的稳定标识（来自 EDID）。CGDirectDisplayID 在重启或重新插拔后会重新分配，
    /// 不能用来认「同一块屏」，这个 UUID 可以。
    /// 取不到时为空字符串（虚拟屏等场景）。
    var uuid: String = ""
    var index: Int
    var name: String
    /// 完整矩形（Quartz 全局坐标，左上原点）
    var frame: CGRect
    /// 去掉菜单栏/Dock 之后的可用矩形（Quartz 全局坐标）
    var visibleFrame: CGRect
}

/// 坐标系转换与显示器解析。
///
/// 三个坐标系要拎清楚：
/// - AX / CGWindowList：全局坐标，原点在**主屏左上角**，y 向下（Quartz）
/// - NSScreen.frame：全局坐标，原点在**主屏左下角**，y 向上（Cocoa）
/// - 窗口相对屏幕的坐标：自己算
enum ScreenGeometry {

    static var mainDisplayID: CGDirectDisplayID { CGMainDisplayID() }

    /// 主屏高度，用于 Cocoa <-> Quartz 转换
    static var primaryHeight: CGFloat { CGDisplayBounds(CGMainDisplayID()).height }

    static func cocoaToQuartz(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryHeight - rect.origin.y - rect.height,
               width: rect.width,
               height: rect.height)
    }

    static func quartzToCocoa(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.origin.x,
               y: primaryHeight - rect.origin.y - rect.height,
               width: rect.width,
               height: rect.height)
    }

    /// 显示器的持久标识。CGDirectDisplayID 每次重启 / 重新插拔都可能变，
    /// 这个 UUID 由显示器 EDID 推导，跨重启稳定。
    static func persistentUUID(of id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return CGMainDisplayID()
    }

    private static let displayCacheLock = NSLock()
    private static var cachedDisplays: [DisplayInfo] = []
    private static var cachedAt = Date.distantPast

    /// 显示器列表。
    ///
    /// NSScreen 查询并不便宜，而扫描 / 恢复一个布局会问它几百次，
    /// 所以这里加一层短 TTL 缓存：一次操作内拿到的是同一份快照，
    /// 又不必几百次重复查询。
    static var currentDisplays: [DisplayInfo] {
        displayCacheLock.lock()
        defer { displayCacheLock.unlock() }
        if cachedDisplays.isEmpty == false, Date().timeIntervalSince(cachedAt) < 2.0 {
            return cachedDisplays
        }
        let displays = NSScreen.screens.enumerated().map { index, screen -> DisplayInfo in
            let id = displayID(of: screen)
            return DisplayInfo(id: id,
                               uuid: persistentUUID(of: id),
                               index: index,
                               name: screen.localizedName,
                               frame: CGDisplayBounds(id),
                               visibleFrame: cocoaToQuartz(screen.visibleFrame))
        }
        cachedDisplays = displays
        cachedAt = Date()
        return displays
    }

    /// 显示器配置变了就清掉缓存
    static func invalidateDisplayCache() {
        displayCacheLock.lock()
        defer { displayCacheLock.unlock() }
        cachedDisplays = []
        cachedAt = .distantPast
    }

    static func display(withID id: CGDirectDisplayID) -> DisplayInfo? {
        currentDisplays.first { $0.id == id }
    }

    /// 找出矩形主要落在哪块显示器上
    static func display(containing rect: CGRect) -> DisplayInfo? {
        display(containing: rect, in: currentDisplays)
    }

    /// 在指定的一组显示器里找主要落点
    static func display(containing rect: CGRect, in displays: [DisplayInfo]) -> DisplayInfo? {
        var best: DisplayInfo?
        var bestArea: CGFloat = 0
        for display in displays {
            let inter = display.frame.intersection(rect)
            guard !inter.isNull else { continue }
            let area = inter.width * inter.height
            if area > bestArea {
                bestArea = area
                best = display
            }
        }
        return best ?? displays.first
    }

    /// 把窗口限制在显示器的可用区域内（至少保证标题栏可见）
    static func clampWithinVisibleArea(_ frame: CGRect, display: DisplayInfo) -> CGRect {
        let area = display.visibleFrame.insetBy(dx: -8, dy: -8)
        var rect = frame
        if rect.width > area.width { rect.size.width = area.width }
        if rect.height > area.height { rect.size.height = area.height }
        if rect.minY < area.minY { rect.origin.y = area.minY }
        if rect.maxY > area.maxY { rect.origin.y = area.maxY - rect.height }
        if rect.minX < area.minX { rect.origin.x = area.minX }
        if rect.maxX > area.maxX { rect.origin.x = area.maxX - rect.width }
        return rect
    }

    /// 为快照算出「现在应该放在哪儿」
    ///
    /// 策略：
    /// 1. 同款显示器还在 → 直接用保存的绝对坐标（最精确）
    /// 2. 显示器没了/换了 → 按序号找一块屏，用归一化坐标投影过去
    /// 3. 完全对不上 → 投到主屏
    /// 找出快照原来在哪块显示器上。
    ///
    /// 优先用 UUID —— 重启后 CGDirectDisplayID 会被重新分配，
    /// 按 id 找可能撞到另一块物理显示器上（这正是「窗口跑到别的屏」的原因）。
    static func matchDisplay(for snapshot: WindowSnapshot, in displays: [DisplayInfo]) -> DisplayInfo? {
        guard displays.isEmpty == false else { return nil }

        // 1. 稳定标识
        if let uuid = snapshot.displayUUID, uuid.isEmpty == false,
           let matched = displays.first(where: { $0.uuid == uuid }) {
            return matched
        }
        // 2. 老数据没有 UUID：屏幕矩形和保存时一模一样，也基本能认定是同一块
        let savedDisplayFrame = snapshot.displayFrame.cgRect
        if savedDisplayFrame.width > 0, savedDisplayFrame.height > 0,
           let matched = displays.first(where: { framesAlmostEqual($0.frame, savedDisplayFrame) }) {
            return matched
        }
        // 3. 再退一步：按保存时的屏幕序号
        if snapshot.displayIndex >= 0, snapshot.displayIndex < displays.count {
            return displays[snapshot.displayIndex]
        }
        // 4. 兜底：窗口中心主要落在哪块屏上
        return display(containing: snapshot.frame.cgRect, in: displays) ?? displays.first
    }

    /// 为快照算出「现在应该放在哪儿」
    ///
    /// - 目标屏幕的位置尺寸和保存时一致：直接用绝对坐标（最精确）
    /// - 屏幕移动过 / 换了排列：用归一化坐标投影到新位置
    static func resolveTarget(for snapshot: WindowSnapshot) -> (frame: CGRect, display: DisplayInfo, remapped: Bool) {
        resolveTarget(for: snapshot, in: currentDisplays)
    }

    /// 同上，但显示器列表由调用方给定（便于测试）
    static func resolveTarget(for snapshot: WindowSnapshot,
                              in displays: [DisplayInfo]) -> (frame: CGRect, display: DisplayInfo, remapped: Bool) {
        let saved = snapshot.frame.cgRect

        guard let target = matchDisplay(for: snapshot, in: displays) else {
            let fallback = DisplayInfo(id: mainDisplayID, uuid: persistentUUID(of: mainDisplayID),
                                       index: 0, name: "主屏",
                                       frame: CGDisplayBounds(mainDisplayID),
                                       visibleFrame: CGDisplayBounds(mainDisplayID))
            return (saved, fallback, true)
        }

        let savedDisplayFrame = snapshot.displayFrame.cgRect
        if framesAlmostEqual(target.frame, savedDisplayFrame) {
            // 屏幕没挪窝，绝对坐标依然有效
            let frame = (saved.width >= 80 && saved.height >= 60)
                ? clampWithinVisibleArea(saved, display: target)
                : saved
            return (frame, target, false)
        }

        // 屏幕位置或尺寸变了，按相对坐标投过去
        let projected = snapshot.relativeFrame.projected(onto: target.frame).cgRect
        return (clampWithinVisibleArea(projected, display: target), target, true)
    }

    /// 两个矩形是否几乎重合（显示器排列没变时用来认定「还是那块屏」）
    static func framesAlmostEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}
