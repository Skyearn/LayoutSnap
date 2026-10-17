import Foundation
import ApplicationServices
import CoreGraphics

/// 当前真实窗口的可读信息
struct WindowDescription {
    var title: String
    var role: String
    var subrole: String
    var frame: CGRect?
}

/// 把「快照」和「当前真实存在的窗口」配对
enum WindowMatcher {

    struct Candidate {
        var snapshot: WindowSnapshot
        var window: AXUIElement?
    }

    static func match(snapshots: [WindowSnapshot], to windows: [AXUIElement]) -> [Candidate] {
        guard !windows.isEmpty else {
            return snapshots.map { Candidate(snapshot: $0, window: nil) }
        }
        guard !snapshots.isEmpty else { return [] }

        let descriptions: [WindowDescription] = windows.map { window in
            WindowDescription(title: AX.string(window, AXAttr.title) ?? "",
                              role: AX.string(window, AXAttr.role) ?? "",
                              subrole: AX.string(window, AXAttr.subrole) ?? "",
                              frame: AX.frame(of: window))
        }

        // 1. 算所有组合的分数
        struct Pair {
            var score: Double
            var snapshotIndex: Int
            var windowIndex: Int
        }

        var pairs: [Pair] = []
        for (si, snapshot) in snapshots.enumerated() {
            for (wi, description) in descriptions.enumerated() {
                let score = scorePair(snapshot: snapshot, description: description)
                if score > 0 { pairs.append(Pair(score: score, snapshotIndex: si, windowIndex: wi)) }
            }
        }
        pairs.sort { $0.score > $1.score }

        // 2. 贪心配对
        var assignedSnapshot = [Int: Int]()   // snapshotIndex -> windowIndex
        var usedWindows = Set<Int>()
        for pair in pairs {
            guard assignedSnapshot[pair.snapshotIndex] == nil else { continue }
            guard !usedWindows.contains(pair.windowIndex) else { continue }
            // 分数太低就别硬凑（主要是标题完全对不上、位置也差很远的情况）
            guard pair.score >= 0.6 else { continue }
            assignedSnapshot[pair.snapshotIndex] = pair.windowIndex
            usedWindows.insert(pair.windowIndex)
        }

        // 3. 剩下的快照按顺序捡剩下的窗口（窗口标题变了也能尽量恢复）
        let leftoverWindows = windows.indices.filter { !usedWindows.contains($0) }
        var leftoverIterator = leftoverWindows.makeIterator()
        let unmatchedSnapshots = snapshots.indices
            .filter { assignedSnapshot[$0] == nil }
            .filter { snapshots[$0].matchTitle?.isEmpty ?? true }
            .sorted { snapshots[$0].zIndex < snapshots[$1].zIndex }

        for snapshotIndex in unmatchedSnapshots {
            if let windowIndex = leftoverIterator.next() {
                assignedSnapshot[snapshotIndex] = windowIndex
                usedWindows.insert(windowIndex)
            } else {
                break
            }
        }

        return snapshots.indices.map { index in
            Candidate(snapshot: snapshots[index],
                      window: assignedSnapshot[index].map { windows[$0] })
        }
    }

    // MARK: - 打分

    private static func scorePair(snapshot: WindowSnapshot, description: WindowDescription) -> Double {
        var score = 0.0

        // 用户给这条记录指定了「匹配关键词」时，必须匹配上，不允许再拿别的窗口凑数
        let hasCustomKeyword = (snapshot.matchTitle?.isEmpty == false)
        let targetText = hasCustomKeyword ? snapshot.effectiveMatchTitle : snapshot.title
        let titleScore = self.titleSimilarity(targetText, description.title)
        if hasCustomKeyword && titleScore == 0 { return 0 }
        score += titleScore * 3.0

        if description.role == snapshot.role { score += 0.4 }
        if !snapshot.subrole.isEmpty && description.subrole == snapshot.subrole { score += 0.6 }

        if let frame = description.frame {
            let target = snapshot.frame.cgRect
            let dx = abs(frame.midX - target.midX)
            let dy = abs(frame.midY - target.midY)
            let distance = sqrt(dx * dx + dy * dy)
            let reference = max(400.0, max(target.width, target.height) * 2)
            score += max(0, 1.0 - distance / reference) * 2.0

            let wRatio = min(frame.width, target.width) / max(1, max(frame.width, target.width))
            let hRatio = min(frame.height, target.height) / max(1, max(frame.height, target.height))
            score += Double((wRatio + hRatio) / 2.0) * 1.0
        }

        return score
    }

    static func normalizeTitle(_ raw: String) -> String {
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("•") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\u{200B}", with: "")
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let a = normalizeTitle(lhs)
        let b = normalizeTitle(rhs)
        if a.isEmpty && b.isEmpty { return 0.35 }
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1.0 }
        if a.contains(b) || b.contains(a) { return 0.8 }

        let wordsA = Set(a.split(separator: " ").map(String.init))
        let wordsB = Set(b.split(separator: " ").map(String.init))
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return Double(intersection) / Double(union) * 0.6
    }
}
