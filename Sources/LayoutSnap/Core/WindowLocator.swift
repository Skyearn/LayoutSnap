import Foundation
import ApplicationServices
import CoreGraphics

/// 在当前真实存在的窗口里，找回某条记录对应的那个窗口。
///
/// 「编辑单个窗口」和「只归位这一个窗口」都要先找到它，
/// 这里复用和恢复流程一样的匹配逻辑，保证认的是同一个窗口。
enum WindowLocator {

    /// 找到对应的 AX 窗口元素
    static func element(for snapshot: WindowSnapshot) -> AXUIElement? {
        guard let pid = AppLauncher.runningPID(snapshot.bundleID) else { return nil }
        let app = AX.application(for: pid)
        AX.limitMessagingTimeout(app, seconds: 1.0)

        let windows = AX.windows(ofApplication: app).filter { window in
            guard let role = AX.string(window, AXAttr.role) else { return false }
            return role == AXRole.window
        }
        guard windows.isEmpty == false else { return nil }

        let candidates = WindowMatcher.match(snapshots: [snapshot], to: windows)
        return candidates.first?.window
    }

    /// 用当前真实窗口的数据刷新这条记录（位置、尺寸、标题、最小化、全屏）
    static func refresh(_ snapshot: WindowSnapshot) -> WindowSnapshot? {
        guard let window = element(for: snapshot) else { return nil }
        AX.limitMessagingTimeout(window, seconds: 1.0)
        guard let rect = AX.frame(of: window) else { return nil }

        var updated = snapshot
        updated.frame = Frame(rect)
        updated.title = AX.string(window, AXAttr.title) ?? snapshot.title
        updated.role = AX.string(window, AXAttr.role) ?? snapshot.role
        updated.subrole = AX.string(window, AXAttr.subrole) ?? snapshot.subrole
        updated.isMinimized = AX.bool(window, AXAttr.minimized) ?? false
        updated.isFullScreen = AX.bool(window, AXAttr.fullScreen) ?? false
        updated.syncDisplayInfo()
        return updated
    }
}
