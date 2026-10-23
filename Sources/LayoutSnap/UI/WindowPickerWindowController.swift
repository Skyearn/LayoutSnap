import AppKit
import SwiftUI

/// 打开选择器之前就已经决定好「存到哪儿」
enum WindowPickerPurpose {
    case createNew(name: String)
    case append(layout: Layout)
    case replace(layout: Layout)

    var summary: String {
        switch self {
        case .createNew(let name):
            return "存成新布局「\(name)」"
        case .append(let layout):
            return "加入「\(layout.displayName)」（原本 \(layout.windows.count) 个）"
        case .replace(let layout):
            return "覆盖「\(layout.displayName)」（原本 \(layout.windows.count) 个）"
        }
    }

    /// 替换和追加有个共同点：都属于某个已有布局
    var existingLayout: Layout? {
        switch self {
        case .createNew: return nil
        case .append(let layout), .replace(let layout): return layout
        }
    }
}

/// 「保存部分窗口」用的选择器：列出当前所有窗口，按应用分组，勾需要的
final class WindowPickerModel: ObservableObject {
    @Published var snapshots: [WindowSnapshot] = []
    @Published var selected: Set<UUID> = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = true

    var selectedSnapshots: [WindowSnapshot] {
        snapshots.filter { selected.contains($0.id) }
    }

    var visibleSnapshots: [WindowSnapshot] {
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.isEmpty == false else { return snapshots }
        return snapshots.filter {
            $0.appName.lowercased().contains(needle) || $0.title.lowercased().contains(needle)
        }
    }

    var groups: [(bundleID: String, appName: String, windows: [WindowSnapshot])] {
        var order: [String] = []
        var buckets: [String: [WindowSnapshot]] = [:]
        for snapshot in visibleSnapshots {
            if buckets[snapshot.bundleID] == nil {
                order.append(snapshot.bundleID)
                buckets[snapshot.bundleID] = []
            }
            buckets[snapshot.bundleID]?.append(snapshot)
        }
        return order.compactMap { bundleID in
            guard let items = buckets[bundleID], let first = items.first else { return nil }
            return (bundleID: bundleID, appName: first.appName, windows: items)
        }
    }

    func isSelected(_ id: UUID) -> Bool {
        selected.contains(id)
    }

    func toggle(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    func setSelection(_ windows: [WindowSnapshot], on: Bool) {
        for window in windows {
            if on {
                selected.insert(window.id)
            } else {
                selected.remove(window.id)
            }
        }
    }
}

struct WindowPickerView: View {

    @ObservedObject var model: WindowPickerModel
    let purpose: WindowPickerPurpose
    let onConfirm: ([WindowSnapshot]) -> Void
    let onCancel: () -> Void

    /// 目标布局里已经存在的窗口（按「应用 + 归一化标题」判定）
    private var existingKeys: Set<String> {
        guard case .append(let layout) = purpose else { return [] }
        return Set(layout.windows.map(\.matchKey))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索应用或窗口标题", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Button("全选") { model.setSelection(model.visibleSnapshots, on: true) }
                Button("全不选") { model.setSelection(model.visibleSnapshots, on: false) }
                Spacer()
                Text("共 \(model.snapshots.count) 个窗口")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text("目标：\(purpose.summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .append = purpose {
                    Text("· 标记「已在布局中」的窗口会更新其位置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    private var content: some View {
        Group {
            if model.isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在扫描窗口…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.groups.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("没有找到窗口").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.groups, id: \.bundleID) { group in
                            appSection(group)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func appSection(_ group: (bundleID: String, appName: String, windows: [WindowSnapshot])) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(nsImage: IconCache.icon(for: group.bundleID))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(group.appName).font(.headline)
                Text("\(group.windows.count) 个窗口")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全选本应用") { model.setSelection(group.windows, on: true) }
                    .buttonStyle(.link)
                Button("全不选") { model.setSelection(group.windows, on: false) }
                    .buttonStyle(.link)
            }
            ForEach(group.windows) { snapshot in
                windowRow(snapshot)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func windowRow(_ snapshot: WindowSnapshot) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { model.isSelected(snapshot.id) },
                set: { _ in model.toggle(snapshot.id) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.displayTitle).lineLimit(1)
                Text(snapshot.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if existingKeys.contains(snapshot.matchKey) {
                Text("已在布局中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(snapshot.id) }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("已选 \(model.selected.count) 个窗口")
                .foregroundStyle(.secondary)
            Spacer()
            Button("取消") { onCancel() }
            Button(primaryTitle) {
                onConfirm(model.selectedSnapshots)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selected.isEmpty || model.isLoading)
        }
        .padding(12)
    }

    private var primaryTitle: String {
        switch purpose {
        case .createNew(let name):
            return "保存为「\(name)」"
        case .append(let layout):
            return "加入「\(layout.displayName)」"
        case .replace(let layout):
            return "覆盖「\(layout.displayName)」"
        }
    }
}

final class WindowPickerWindowController: NSWindowController {

    private let model = WindowPickerModel()
    private weak var controller: AppController?
    var onClose: (() -> Void)?

    init(controller: AppController) {
        self.controller = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "选择要保存的窗口"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 400)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(purpose: WindowPickerPurpose) {
        guard let controller else { return }

        let view = WindowPickerView(
            model: model,
            purpose: purpose,
            onConfirm: { [weak self] snapshots in
                guard let self else { return }
                self.close()
                controller.applyPickedWindows(snapshots, purpose: purpose)
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )

        let container = NSView()
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        window?.contentView = container
        model.selected.removeAll()
        model.isLoading = true

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)

        controller.scanCurrentWindows { [weak self] snapshots in
            guard let self else { return }
            self.model.snapshots = snapshots
            self.model.isLoading = false
        }
    }

    override func close() {
        super.close()
        onClose?()
    }
}
