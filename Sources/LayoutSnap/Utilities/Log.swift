import Foundation

/// 极简日志：写文件 + 输出到 stderr（用 `log stream` 或 Console.app 也能看到）
enum Log {
    private static let queue = DispatchQueue(label: "com.layoutsnap.log")
    private static let fm = FileManager.default

    static let directory: URL = {
        let base = fm.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library")
        let dir = base.appendingPathComponent("Logs/LayoutSnap", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let fileURL: URL = directory.appendingPathComponent("LayoutSnap.log")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ tag: String, _ message: String) {
        let line = "[\(formatter.string(from: Date()))] [\(tag)] \(message)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                if let data = line.data(using: .utf8) { try? handle.write(contentsOf: data) }
            } else {
                try? line.data(using: .utf8)?.write(to: fileURL)
            }
        }
        FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
    }

    static func info(_ message: String) { write("info", message) }
    static func error(_ message: String) { write("error", message) }

    /// 日志文件太大时截断，避免无限增长
    static func rotateIfNeeded(maxBytes: Int = 2_000_000) {
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size > maxBytes else { return }
        let backup = directory.appendingPathComponent("LayoutSnap.log.1")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: fileURL, to: backup)
    }
}
