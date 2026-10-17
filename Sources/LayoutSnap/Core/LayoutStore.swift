import Foundation
import Combine

/// 布局的持久化存储：~/Library/Application Support/LayoutSnap/layouts.json
final class LayoutStore: ObservableObject {

    static let shared = LayoutStore()

    @Published private(set) var layouts: [Layout] = []

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.layoutsnap.store")

    let directory: URL
    let fileURL: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private convenience init() {
        self.init(directory: LayoutStore.resolveDirectory())
    }

    /// 指定目录的实例。自检和测试用它，免得动到用户真实的布局文件。
    init(directory: URL) {
        self.directory = directory
        fileURL = directory.appendingPathComponent("layouts.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    /// 找一个真的能写的目录。必要时可以用环境变量 WINDOWSNAP_DATA_DIR 指定
    /// （测试或者把数据放到同步盘里时很方便）。
    private static func resolveDirectory() -> URL {
        let manager = FileManager.default
        var candidates: [URL] = []

        if let custom = ProcessInfo.processInfo.environment["WINDOWSNAP_DATA_DIR"], !custom.isEmpty {
            candidates.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true))
        }
        if let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(base.appendingPathComponent("LayoutSnap", isDirectory: true))
        }
        candidates.append(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".layoutsnap", isDirectory: true))

        for candidate in candidates {
            do {
                try manager.createDirectory(at: candidate, withIntermediateDirectories: true)
                let probe = candidate.appendingPathComponent(".write-probe")
                try Data("ok".utf8).write(to: probe)
                try? manager.removeItem(at: probe)
                migrateLegacyDataIfNeeded(into: candidate)
                return candidate
            } catch {
                Log.error("数据目录不可用 \(candidate.path)：\(error.localizedDescription)")
            }
        }
        Log.error("找不到可写的数据目录，布局将无法保存")
        return candidates.first ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    /// 老版本应用叫 WindowSnap，目录名跟着是 WindowSnap。
    /// 改名后第一次启动时把布局文件搬过来，避免用户丢数据。
    private static func migrateLegacyDataIfNeeded(into directory: URL) {
        let manager = FileManager.default
        let newFile = directory.appendingPathComponent("layouts.json")
        guard manager.fileExists(atPath: newFile.path) == false else { return }

        let legacyDirectory = directory.deletingLastPathComponent()
            .appendingPathComponent("WindowSnap", isDirectory: true)
        let legacyFile = legacyDirectory.appendingPathComponent("layouts.json")
        guard manager.fileExists(atPath: legacyFile.path) else { return }

        do {
            try manager.copyItem(at: legacyFile, to: newFile)
            Log.info("已从旧目录迁移布局数据：\(legacyDirectory.path)")
        } catch {
            Log.error("迁移旧布局数据失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 读写

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            layouts = []
            return
        }
        do {
            layouts = try decoder.decode([Layout].self, from: data)
            Log.info("载入 \(layouts.count) 个布局")
        } catch {
            Log.error("布局文件解析失败: \(error)")
            // 别把人家的文件覆盖了，先备份
            let backup = directory.appendingPathComponent("layouts.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? data.write(to: backup)
            layouts = []
        }
    }

    func save() {
        let snapshot = layouts
        let url = fileURL
        do {
            let data = try encoder.encode(snapshot)
            let temporary = url.appendingPathExtension("tmp")
            try data.write(to: temporary)
            _ = try? fileManager.removeItem(at: url)
            try fileManager.moveItem(at: temporary, to: url)
        } catch {
            Log.error("保存布局失败: \(error)")
        }
    }

    // MARK: - 增删改

    @discardableResult
    func add(name: String, windows: [WindowSnapshot], triggerBundleIDs: [String] = []) -> Layout {
        var layout = Layout(name: name, windows: windows)
        layout.triggerBundleIDs = triggerBundleIDs
        // 扫描出来的 zIndex 是从窗口列表里取的序号（可能有空洞），
        // 统一按数组顺序重新编号，恢复时的叠放次序才和列表顺序一致。
        renumber(&layout)
        layouts.append(layout)
        save()
        return layout
    }

    func update(id: UUID, windows: [WindowSnapshot]) {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        layouts[index].windows = windows
        layouts[index].updatedAt = Date()
        save()
    }

    func rename(id: UUID, to name: String) {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        // 允许暂时为空（界面里正在输入），显示时会用 displayName 兜底
        layouts[index].name = name
        layouts[index].updatedAt = Date()
        save()
    }

    func remove(id: UUID) {
        layouts.removeAll { $0.id == id }
        save()
    }

    func setHotKey(_ hotKey: HotKeySpec?, for id: UUID) {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        // 同一个快捷键不能绑两个布局，先解绑旧的
        if let hotKey {
            for i in layouts.indices where i != index && layouts[i].hotKey == hotKey {
                layouts[i].hotKey = nil
            }
        }
        layouts[index].hotKey = hotKey
        save()
    }

    func setTriggers(_ bundleIDs: [String], for id: UUID) {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        layouts[index].triggerBundleIDs = bundleIDs
        save()
    }

    func layout(id: UUID) -> Layout? {
        layouts.first { $0.id == id }
    }

    func layout(withHotKey hotKey: HotKeySpec) -> Layout? {
        layouts.first { $0.hotKey == hotKey }
    }

    func layouts(triggeredBy bundleID: String) -> [Layout] {
        layouts.filter { $0.triggerBundleIDs.contains(bundleID) }
    }

    private func nextFreeHotKey() -> HotKeySpec? {
        let used = Set(layouts.compactMap { $0.hotKey })
        return HotKeySpec.all.first { !used.contains($0) }
    }

    // MARK: - 单个窗口级别的编辑

    /// 往布局里加窗口。
    /// 同一个应用 + 同一个标题的窗口已经在里面时，用新位置覆盖它，而不是加出一条重复记录。
    func addWindows(_ snapshots: [WindowSnapshot], to layoutID: UUID) {
        guard let index = layouts.firstIndex(where: { $0.id == layoutID }) else { return }
        for var snapshot in snapshots {
            let existing = layouts[index].windows.firstIndex {
                $0.bundleID == snapshot.bundleID && $0.displayTitle == snapshot.displayTitle
            }
            if let existing {
                snapshot.id = layouts[index].windows[existing].id
                layouts[index].windows[existing] = snapshot
            } else {
                layouts[index].windows.append(snapshot)
            }
        }
        renumber(&layouts[index])
        layouts[index].updatedAt = Date()
        save()
    }

    /// 用一批新窗口整个替换掉某个布局的内容（「保存到已有布局」用）
    func replaceWindows(_ snapshots: [WindowSnapshot], in layoutID: UUID) {
        guard let index = layouts.firstIndex(where: { $0.id == layoutID }) else { return }
        layouts[index].windows = snapshots
        renumber(&layouts[index])
        layouts[index].updatedAt = Date()
        save()
    }

    /// 改一条窗口记录（位置、尺寸、匹配关键词、启用状态…）
    func updateWindow(_ snapshot: WindowSnapshot, in layoutID: UUID) {
        guard let index = layouts.firstIndex(where: { $0.id == layoutID }) else { return }
        guard let windowIndex = layouts[index].windows.firstIndex(where: { $0.id == snapshot.id }) else {
            addWindows([snapshot], to: layoutID)
            return
        }
        layouts[index].windows[windowIndex] = snapshot
        layouts[index].updatedAt = Date()
        save()
    }

    /// 从布局里删掉若干窗口
    func removeWindows(ids: Set<UUID>, from layoutID: UUID) {
        guard let index = layouts.firstIndex(where: { $0.id == layoutID }) else { return }
        layouts[index].windows.removeAll { ids.contains($0.id) }
        renumber(&layouts[index])
        layouts[index].updatedAt = Date()
        save()
    }

    /// 把某个应用在本布局里的窗口全删掉
    @discardableResult
    func removeApp(bundleID: String, from layoutID: UUID) -> Int {
        guard let index = layouts.firstIndex(where: { $0.id == layoutID }) else { return 0 }
        let before = layouts[index].windows.count
        layouts[index].windows.removeAll { $0.bundleID == bundleID }
        renumber(&layouts[index])
        layouts[index].updatedAt = Date()
        save()
        return before - layouts[index].windows.count
    }

    /// 批量启用/停用窗口
    func setWindowsEnabled(_ enabled: Bool, ids: Set<UUID>, in layoutID: UUID) {
        guard let index = layouts.firstIndex(where: { $0.id == layoutID }) else { return }
        for windowIndex in layouts[index].windows.indices
        where ids.contains(layouts[index].windows[windowIndex].id) {
            layouts[index].windows[windowIndex].isEnabled = enabled
        }
        layouts[index].updatedAt = Date()
        save()
    }

    /// 调整一条记录的前后顺序（direction 为 -1 往前、1 往后）
    func moveWindow(id: UUID, direction: Int, in layoutID: UUID) {
        guard let index = layouts.firstIndex(where: { $0.id == layoutID }) else { return }
        guard let windowIndex = layouts[index].windows.firstIndex(where: { $0.id == id }) else { return }
        let target = windowIndex + direction
        guard target >= 0, target < layouts[index].windows.count else { return }
        layouts[index].windows.swapAt(windowIndex, target)
        renumber(&layouts[index])
        layouts[index].updatedAt = Date()
        save()
    }

    /// zIndex 按数组顺序重新编号（0 在最前面），恢复时据此还原叠放次序
    private func renumber(_ layout: inout Layout) {
        for index in layout.windows.indices {
            layout.windows[index].zIndex = index
        }
    }

    // MARK: - 导入导出（备份用）

    func export(to url: URL) throws {
        let data = try encoder.encode(layouts)
        try data.write(to: url)
    }

    func `import`(from url: URL, replace: Bool = false) throws {
        let data = try Data(contentsOf: url)
        let imported = try decoder.decode([Layout].self, from: data)
        if replace {
            layouts = imported
        } else {
            // 名字重复的自动加后缀
            var existingNames = Set(layouts.map(\.name))
            var merged = imported
            for index in merged.indices {
                if existingNames.contains(merged[index].name) {
                    var n = 2
                    while existingNames.contains("\(merged[index].name) \(n)") { n += 1 }
                    merged[index].name = "\(merged[index].name) \(n)"
                }
                merged[index].id = UUID()
                existingNames.insert(merged[index].name)
            }
            layouts.append(contentsOf: merged)
        }
        save()
    }
}
