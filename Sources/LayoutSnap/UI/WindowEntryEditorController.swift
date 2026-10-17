import AppKit
import SwiftUI

/// 单条窗口记录的编辑器：改坐标尺寸、改匹配关键词、停用、删除
final class WindowEntryEditorModel: ObservableObject {

    @Published var snapshot: WindowSnapshot
    @Published var matchTitleText: String
    @Published var statusText: String = ""
    @Published var isLocating: Bool = false

    let layoutID: UUID
    let layoutName: String

    private let controller: AppController
    var onClose: (() -> Void)?

    init(snapshot: WindowSnapshot, layoutID: UUID, layoutName: String, controller: AppController) {
        self.snapshot = snapshot
        self.layoutID = layoutID
        self.layoutName = layoutName
        self.controller = controller
        self.matchTitleText = snapshot.matchTitle ?? ""
    }

    /// 当前这条坐标落在哪块显示器上（实时跟随输入框变化）
    var currentDisplayName: String {
        ScreenGeometry.display(containing: snapshot.frame.cgRect)?.name ?? "屏幕外"
    }

    var windowDescription: String {
        "\(snapshot.appName) · \(snapshot.title.isEmpty ? "(无标题)" : snapshot.title)"
    }

    func save() {
        var updated = snapshot
        let trimmed = matchTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.matchTitle = trimmed.isEmpty ? nil : trimmed
        updated.relativeFrame = updated.frame.relative(to: currentDisplayFrame)
        updated.syncDisplayInfo()
        controller.store.updateWindow(updated, in: layoutID)
        controller.statusBar?.flash("已保存「\(updated.displayTitle)」的修改")
        onClose?()
    }

    func delete() {
        controller.store.removeWindows(ids: [snapshot.id], from: layoutID)
        controller.statusBar?.flash("已从「\(layoutName)」里移除「\(snapshot.displayTitle)」")
        onClose?()
    }

    /// 读一下这个窗口现在真实的位置，回填到输入框
    func refreshFromCurrent() {
        isLocating = true
        statusText = "正在读取…"
        controller.locateCurrentWindow(for: snapshot) { [weak self] updated in
            guard let self else { return }
            self.isLocating = false
            guard let updated else {
                self.statusText = "现在找不到这个窗口（应用没开或窗口关掉了）"
                return
            }
            var merged = updated
            merged.id = self.snapshot.id
            merged.matchTitle = self.snapshot.matchTitle
            merged.isEnabled = self.snapshot.isEnabled
            self.snapshot = merged
            self.statusText = "已读取当前窗口的位置和尺寸"
        }
    }

    /// 把窗口挪到某块显示器的中央（改完坐标可以马上「归位」看看效果）
    func centerOnMainDisplay() {
        guard let display = ScreenGeometry.currentDisplays.first else { return }
        let visible = display.visibleFrame
        var frame = snapshot.frame
        frame.width = min(frame.width, Double(visible.width))
        frame.height = min(frame.height, Double(visible.height))
        frame.x = Double(visible.minX) + (Double(visible.width) - frame.width) / 2
        frame.y = Double(visible.minY) + (Double(visible.height) - frame.height) / 2
        snapshot.frame = frame
        statusText = "已居中到 \(display.name)（还需要保存）"
    }

    private var currentDisplayFrame: CGRect {
        ScreenGeometry.display(containing: snapshot.frame.cgRect)?.frame ?? CGDisplayBounds(CGMainDisplayID())
    }
}

struct WindowEntryEditorView: View {
    @ObservedObject var model: WindowEntryEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            coordinateFields
            Divider()
            options
            Divider()
            actions
        }
        .padding(16)
        .frame(width: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(nsImage: IconCache.icon(for: model.snapshot.bundleID))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(model.windowDescription)
                    .font(.headline)
                    .lineLimit(1)
            }
            Text("所在布局：\(model.layoutName)　当前显示器：\(model.currentDisplayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var coordinateFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("X")
                    TextField("", value: $model.snapshot.frame.x, format: .number)
                        .frame(width: 92)
                    Text("Y")
                    TextField("", value: $model.snapshot.frame.y, format: .number)
                        .frame(width: 92)
                }
                GridRow {
                    Text("宽")
                    TextField("", value: $model.snapshot.frame.width, format: .number)
                        .frame(width: 92)
                    Text("高")
                    TextField("", value: $model.snapshot.frame.height, format: .number)
                        .frame(width: 92)
                }
            }
            HStack(spacing: 10) {
                Button("取当前窗口位置") { model.refreshFromCurrent() }
                Button("居中到主屏") { model.centerOnMainDisplay() }
                if model.isLocating {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("坐标是全局坐标（左上角为原点，跟「显示器偏好设置」里看到的一致）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("参与恢复", isOn: $model.snapshot.isEnabled)
            Toggle("恢复时最小化这个窗口", isOn: $model.snapshot.isMinimized)
            Toggle("恢复时切到全屏", isOn: $model.snapshot.isFullScreen)
            HStack(spacing: 8) {
                Text("匹配关键词")
                TextField("留空就用窗口标题", text: $model.matchTitleText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            Text("窗口标题会变（浏览器标签页、正在编辑的文档）的时候，在这里填一段固定关键词，恢复时就靠它认窗口。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Button("从布局里删除") { model.delete() }
            Spacer()
            Button("取消") { model.onClose?() }
            Button("保存") { model.save() }
                .buttonStyle(.borderedProminent)
        }
    }
}

final class WindowEntryEditorController: NSWindowController {

    private let model: WindowEntryEditorModel
    var onClose: (() -> Void)?

    init(snapshot: WindowSnapshot, layoutID: UUID, layoutName: String, controller: AppController) {
        model = WindowEntryEditorModel(snapshot: snapshot,
                                       layoutID: layoutID,
                                       layoutName: layoutName,
                                       controller: controller)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "编辑窗口记录"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        model.onClose = { [weak self] in
            self?.close()
        }

        let container = NSView()
        let hosting = NSHostingView(rootView: WindowEntryEditorView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        window.contentView = container
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    override func close() {
        super.close()
        onClose?()
    }
}
