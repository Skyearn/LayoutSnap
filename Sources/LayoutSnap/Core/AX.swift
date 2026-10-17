import Foundation
import ApplicationServices
import AppKit

/// 属性名直接用字符串常量，省得跟 SDK 里 CFString/String 的桥接打架
enum AXAttr {
    static let windows = "AXWindows"
    static let position = "AXPosition"
    static let size = "AXSize"
    static let title = "AXTitle"
    static let role = "AXRole"
    static let subrole = "AXSubrole"
    static let minimized = "AXMinimized"
    static let fullScreen = "AXFullScreen"
    static let enhancedUserInterface = "AXEnhancedUserInterface"
    static let focusedWindow = "AXFocusedWindow"
    static let mainWindow = "AXMainWindow"
    static let closeButton = "AXCloseButton"
    static let hidden = "AXHidden"
    static let children = "AXChildren"
    static let appIsActive = "AXFrontmost"
}

enum AXAction {
    static let raise = "AXRaise"
    static let press = "AXPress"
}

enum AXRole {
    static let window = "AXWindow"
    static let standardWindow = "AXStandardWindow"
    static let dialog = "AXDialog"
    static let sheet = "AXSheet"
    static let systemDialog = "AXSystemDialog"
}

/// Accessibility API 的薄封装
enum AX {

    // MARK: - 权限

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermissionPrompt() {
        // "AXTrustedCheckOptionPrompt" 就是 kAXTrustedCheckOptionPrompt 的字面值
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    // MARK: - 读取

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func int(_ element: AXUIElement, _ attribute: String) -> Int? {
        (copy(element, attribute) as? NSNumber)?.intValue
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        if let number = copy(element, attribute) as? NSNumber { return number.boolValue }
        if let value = copy(element, attribute) as? Bool { return value }
        return nil
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let array = copy(element, attribute) as? [AXUIElement] else { return [] }
        return array
    }

    /// 取一个「值是 AXUIElement」的属性（比如 AXFocusedWindow）。
    /// CFTypeRef 到 AXUIElement 的转换要显式做，条件转换编译器不让写。
    static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = copy(element, attribute) else { return nil }
        guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    static func windows(ofApplication application: AXUIElement) -> [AXUIElement] {
        elements(application, AXAttr.windows)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var value = CGPoint.zero
        guard AXValueGetValue(raw as! AXValue, .cgPoint, &value) else { return nil }
        return value
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var value = CGSize.zero
        guard AXValueGetValue(raw as! AXValue, .cgSize, &value) else { return nil }
        return value
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = point(element, AXAttr.position),
              let size = size(element, AXAttr.size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - 写入

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) -> Bool {
        set(element, attribute, value as CFBoolean)
    }

    @discardableResult
    static func setPoint(_ element: AXUIElement, _ attribute: String, _ point: CGPoint) -> Bool {
        var mutable = point
        guard let value = AXValueCreate(.cgPoint, &mutable) else { return false }
        return set(element, attribute, value)
    }

    @discardableResult
    static func setSize(_ element: AXUIElement, _ attribute: String, _ size: CGSize) -> Bool {
        var mutable = size
        guard let value = AXValueCreate(.cgSize, &mutable) else { return false }
        return set(element, attribute, value)
    }

    @discardableResult
    static func setFrameOrigin(_ element: AXUIElement, _ origin: CGPoint) -> Bool {
        setPoint(element, AXAttr.position, origin)
    }

    @discardableResult
    static func setFrameSize(_ element: AXUIElement, _ size: CGSize) -> Bool {
        setSize(element, AXAttr.size, size)
    }

    // MARK: - 其它

    static func application(for pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// 卡死的应用会把 AX 调用拖到默认超时（好几秒），统一压到 1 秒内
    static func limitMessagingTimeout(_ element: AXUIElement, seconds: Float = 1.0) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    static func isValidWindow(_ element: AXUIElement) -> Bool {
        guard let role = string(element, AXAttr.role), role == AXRole.window else { return false }
        // 有些窗口一查属性就报错，说明已经没了
        return frame(of: element) != nil
    }
}
