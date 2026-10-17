import Foundation

/// Carbon 虚拟键码表。这些键码和 NSEvent.keyCode 是同一套，
/// 所以录制热键的时候可以直接拿来用。
enum KeyCodeMap {

    /// 主键盘数字 1-9
    static let digitKeyCodes: [Int: UInt32] = [
        1: 0x12, 2: 0x13, 3: 0x14,
        4: 0x15, 5: 0x17, 6: 0x16,
        7: 0x1A, 8: 0x1C, 9: 0x19
    ]

    /// ⌃Z 用的 Z
    static let z: UInt32 = 0x06

    /// 从修饰键掩码生成显示前缀
    static func modifierDisplay(_ carbon: UInt32) -> String {
        var text = ""
        if carbon & 0x1000 != 0 { text += "⌃" }   // control
        if carbon & 0x0800 != 0 { text += "⌥" }   // option
        if carbon & 0x0200 != 0 { text += "⇧" }   // shift
        if carbon & 0x0100 != 0 { text += "⌘" }   // command
        return text
    }

    /// 不太好用字符表示的那些键
    private static let specialNames: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "Esc", 76: "⌤", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'",
        43: ",", 47: ".", 44: "/", 42: "\\", 50: "`"
    ]

    /// 菜单里显示用的按键字符（AppKit 的 keyEquivalent）
    private static let menuEquivalents: [UInt32: String] = [
        36: "\r", 48: "\t", 49: " ", 51: "\u{8}", 53: "\u{1b}", 76: "\u{3}",
        117: "\u{7F}",
        115: "\u{F771}", 119: "\u{F773}", 116: "\u{F72C}", 121: "\u{F72D}",
        123: "\u{F702}", 124: "\u{F703}", 125: "\u{F701}", 126: "\u{F700}",
        122: "\u{F704}", 120: "\u{F705}", 99: "\u{F706}", 118: "\u{F707}",
        96: "\u{F708}", 97: "\u{F709}", 98: "\u{F70A}", 100: "\u{F70B}",
        101: "\u{F70C}", 109: "\u{F70D}", 103: "\u{F70E}", 111: "\u{F70F}"
    ]

    static func specialName(_ keyCode: UInt32) -> String? {
        specialNames[keyCode]
    }

    static func menuKeyEquivalent(_ keyCode: UInt32) -> String? {
        menuEquivalents[keyCode]
    }
}
