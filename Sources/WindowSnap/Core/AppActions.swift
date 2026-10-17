import Foundation

/// 全局动作。这些快捷键是「功能」级别的，和某个具体布局无关。
///
/// 命名约定：
/// - 「添加…」= 追加到已有布局，不影响布局里原有的窗口记录
/// - 「保存…」= 用当前内容整体覆盖目标布局（快照语义）
enum AppAction: String, CaseIterable, Identifiable {
    case restoreLayout
    case addCurrentWindow
    case addPartialWindows
    case savePartialWindows
    case saveAllWindows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restoreLayout: return "恢复布局"
        case .addCurrentWindow: return "添加当前窗口"
        case .addPartialWindows: return "添加部分窗口"
        case .savePartialWindows: return "保存部分窗口"
        case .saveAllWindows: return "保存所有窗口"
        }
    }

    var symbol: String {
        switch self {
        case .restoreLayout: return "arrow.uturn.backward"
        case .addCurrentWindow: return "macwindow"
        case .addPartialWindows: return "checklist"
        case .savePartialWindows: return "square.on.square"
        case .saveAllWindows: return "rectangle.3.group"
        }
    }

    /// 选已有布局时是追加还是覆盖
    var isAppend: Bool {
        switch self {
        case .addCurrentWindow, .addPartialWindows: return true
        case .restoreLayout, .savePartialWindows, .saveAllWindows: return false
        }
    }

    var detail: String {
        switch self {
        case .restoreLayout:
            return "恢复最近用过的那个布局；没有用过的话会打开菜单让你挑"
        case .addCurrentWindow:
            return "把当前正在用的那个窗口加到最近使用的布局里，不影响布局里的其他窗口"
        case .addPartialWindows:
            return "勾选若干窗口，加到最近使用的布局里"
        case .savePartialWindows:
            return "勾选若干窗口，用它们整体覆盖最近使用的布局"
        case .saveAllWindows:
            return "把当前所有窗口保存成布局；选择已有布局时会整体覆盖它"
        }
    }

    /// 只有「恢复布局」有默认快捷键，其他都留空由用户自己设
    var defaultHotKey: HotKeySpec? {
        switch self {
        case .restoreLayout: return .defaultRestore
        default: return nil
        }
    }
}
