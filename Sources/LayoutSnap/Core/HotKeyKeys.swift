import AppKit
import Carbon.HIToolbox

/// NSEvent（录制热键时拿到的）和 Carbon（注册热键时要的）之间的换算
enum HotKeyKeys {

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.control) { value |= HotKeySpec.control }
        if flags.contains(.option) { value |= HotKeySpec.option }
        if flags.contains(.shift) { value |= HotKeySpec.shift }
        if flags.contains(.command) { value |= HotKeySpec.command }
        return value
    }

    static func modifierFlags(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & HotKeySpec.control != 0 { flags.insert(.control) }
        if carbon & HotKeySpec.option != 0 { flags.insert(.option) }
        if carbon & HotKeySpec.shift != 0 { flags.insert(.shift) }
        if carbon & HotKeySpec.command != 0 { flags.insert(.command) }
        return flags
    }

    /// 按键在界面上显示成什么
    static func keyDisplay(keyCode: UInt32, characters: String?) -> String {
        if let name = KeyCodeMap.specialName(keyCode) { return name }
        if let characters, characters.isEmpty == false {
            return characters.uppercased()
        }
        return "键\(keyCode)"
    }

    /// 菜单右侧那列用的字符
    static func menuKeyEquivalent(keyCode: UInt32, characters: String?) -> String? {
        if let equivalent = KeyCodeMap.menuKeyEquivalent(keyCode) { return equivalent }
        guard let characters, characters.count == 1 else { return nil }
        guard let scalar = characters.unicodeScalars.first, scalar.value >= 32 else { return nil }
        return characters.lowercased()
    }

    /// 从一次按键生成热键定义。必须带至少一个修饰键，
    /// 否则会变成一个全局裸按键，把正常打字全吃了。
    static func spec(from event: NSEvent) -> HotKeySpec? {
        let carbon = carbonModifiers(from: event.modifierFlags)
        guard carbon != 0 else { return nil }

        let keyCode = UInt32(event.keyCode)
        let characters = printableCharacters(of: event)
        let display = KeyCodeMap.modifierDisplay(carbon) + keyDisplay(keyCode: keyCode, characters: characters)
        return HotKeySpec(keyCode: keyCode,
                          carbonModifiers: carbon,
                          display: display,
                          keyEquivalent: menuKeyEquivalent(keyCode: keyCode, characters: characters))
    }

    /// 拿忽略修饰键之后的字符，去掉控制字符
    private static func printableCharacters(of event: NSEvent) -> String? {
        guard let characters = event.charactersIgnoringModifiers, characters.isEmpty == false else { return nil }
        let filtered = characters.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }
        let text = String(String.UnicodeScalarView(filtered))
        return text.isEmpty ? nil : text
    }

    /// 特别常用的几个修饰键组合，显示成人话
    static func describe(_ spec: HotKeySpec) -> String {
        "\(spec.display)"
    }
}
