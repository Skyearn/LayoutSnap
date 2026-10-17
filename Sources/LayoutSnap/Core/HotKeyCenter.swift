import Foundation
import Carbon.HIToolbox

/// 一条热键绑定：谁（id）绑了什么键
struct HotKeyBinding: Hashable {
    var id: String
    var spec: HotKeySpec
}

/// 全局热键（Carbon RegisterEventHotKey）
///
/// 用 Carbon 而不是 NSEvent 全局监听，好处是：
/// - 注册的是系统级热键，不需要「输入监控」权限
/// - 不会吞掉别的按键
final class HotKeyCenter {

    static let shared = HotKeyCenter()

    /// 某条绑定被按下，回传它的 id
    var onTrigger: ((String) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var bindingIDByRegistration: [UInt32: String] = [:]
    private var nextRegistrationID: UInt32 = 1

    private static let signature: OSType = 0x57534E50   // 'LSNP'

    private init() {
        installHandler()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            center.handle(registrationID: hotKeyID.id)
            return noErr
        }

        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         callback,
                                         1,
                                         &eventType,
                                         Unmanaged.passUnretained(self).toOpaque(),
                                         &eventHandler)
        if status != noErr {
            Log.error("安装热键事件处理器失败: \(status)")
        }
    }

    private func handle(registrationID: UInt32) {
        guard let bindingID = bindingIDByRegistration[registrationID] else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?(bindingID)
        }
    }

    /// 重新注册一组绑定（先全部注销）。同一个键被绑了两次时只保留第一条。
    func reload(_ bindings: [HotKeyBinding]) {
        unregisterAll()
        var used: [HotKeySpec] = []
        for binding in bindings {
            guard binding.spec.isEmpty == false else { continue }
            if used.contains(where: { $0.conflicts(with: binding.spec) }) {
                Log.error("热键 \(binding.spec.display) 被绑了两次，跳过 \(binding.id)")
                continue
            }
            if register(binding) {
                used.append(binding.spec)
            }
        }
        Log.info("热键注册完成，共 \(registrations.count) 个")
    }

    @discardableResult
    private func register(_ binding: HotKeyBinding) -> Bool {
        let registrationID = nextRegistrationID
        nextRegistrationID += 1
        let hotKeyID = EventHotKeyID(signature: HotKeyCenter.signature, id: registrationID)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.spec.keyCode,
                                         binding.spec.carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &reference)
        guard status == noErr, let reference else {
            Log.error("热键 \(binding.spec.display) 注册失败（可能被系统或别的应用占用了），错误码 \(status)")
            return false
        }
        registrations[registrationID] = reference
        bindingIDByRegistration[registrationID] = binding.id
        return true
    }

    private func unregisterAll() {
        for (_, reference) in registrations {
            UnregisterEventHotKey(reference)
        }
        registrations.removeAll()
        bindingIDByRegistration.removeAll()
    }

    /// 某个快捷键现在能不能注册成功（设置界面里用来提前提醒）
    func isAvailable(_ spec: HotKeySpec) -> Bool {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotKeyCenter.signature, id: 0)
        let status = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &reference)
        if let reference { UnregisterEventHotKey(reference) }
        return status == noErr
    }

    func teardown() {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
