import AppKit
import SwiftUI

/// 录制一个全局快捷键。
///
/// 点按钮进入录制状态，然后按下想用的组合键：Esc 取消，Delete 清除。
/// 录制期间会把已经注册的全局热键临时注销——不然你按下的组合键
/// 会立刻把原来绑定的那个动作触发掉。
final class HotKeyRecorder: ObservableObject {

    @Published var isRecording = false
    @Published var isRejected = false

    /// 录到新快捷键（nil 表示清除）
    var onChange: ((HotKeySpec?) -> Void)?

    private var monitor: Any?

    deinit {
        stop()
    }

    func start() {
        stop()
        isRejected = false
        isRecording = true
        AppController.shared.setHotKeysSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            self.handle(event)
            return nil    // 录制期间把按键吃掉
        }
    }

    func stop() {
        guard isRecording || monitor != nil else { return }
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        AppController.shared.setHotKeysSuspended(false)
    }

    private func handle(_ event: NSEvent) {
        switch event.keyCode {
        case 53:            // Esc：放弃这次录制
            stop()
            return
        case 51, 117:       // Delete / 前向删除：清除快捷键
            onChange?(nil)
            stop()
            return
        default:
            break
        }
        guard let spec = HotKeyKeys.spec(from: event) else {
            isRejected = true
            return
        }
        onChange?(spec)
        stop()
    }
}

/// 一行「功能 + 当前快捷键 + 录制按钮」
struct HotKeyRow: View {

    let title: String
    let detail: String
    let symbol: String
    let spec: HotKeySpec?
    let onChange: (HotKeySpec?) -> Void

    @StateObject private var recorder = HotKeyRecorder()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if recorder.isRejected {
                Text("要加修饰键")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start()
                }
            } label: {
                Text(recorder.isRecording ? "按下组合键…" : (spec?.display ?? "未设置"))
                    .frame(minWidth: 100)
            }
            .buttonStyle(.bordered)
            .tint(recorder.isRecording ? Color.accentColor : nil)

            Button {
                onChange(nil)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("清除快捷键")
            .disabled(spec == nil)
        }
        .padding(.vertical, 2)
        .onAppear {
            recorder.onChange = { newSpec in
                onChange(newSpec)
            }
        }
        .onDisappear {
            recorder.stop()
        }
    }
}
