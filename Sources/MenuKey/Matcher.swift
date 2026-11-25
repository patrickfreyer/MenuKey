import Foundation

/// Small fuzzy matcher: substring hits beat scattered subsequence hits,
/// word-start hits beat mid-word hits, title beats parent-menu path.
enum Matcher {
    static func rank(_ entries: [MenuEntry], query: String, usage: [String: Int]) -> [MenuEntry] {
        let tokens = MenuEntry.normalize(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map { Array($0) }

        if tokens.isEmpty {
            // Recently used first, then original menu order.
            return entries.sorted { a, b in
                let ua = usage[a.usageKey] ?? 0, ub = usage[b.usageKey] ?? 0
                return ua != ub ? ua > ub : a.id < b.id
            }
        }

        var scored: [(MenuEntry, Int)] = []
        scored.reserveCapacity(entries.count)
        outer: for e in entries {
            var total = 0
            for t in tokens {
                let titleScore = score(t, e.titleKey).map { $0 * 2 }
                let pathScore = score(t, e.pathKey)
                guard let best = [titleScore, pathScore].compactMap({ $0 }).max() else { continue outer }
                total += best
            }
            total += min(usage[e.usageKey] ?? 0, 10) * 60
            total -= e.titleKey.count // prefer shorter, more specific titles
            scored.append((e, total))
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }.map(\.0)
    }

    static func score(_ q: [Character], _ t: [Character]) -> Int? {
        guard !q.isEmpty else { return 0 }
        guard q.count <= t.count else { return nil }

        // Contiguous substring
        if let idx = firstIndex(of: q, in: t) {
            var s = 1000 - idx
            if idx == 0 { s += 500 } else if isBoundary(t, idx) { s += 300 }
            return s
        }

        // Subsequence
        var s = 0, ti = 0, prev = -2
        for c in q {
            var found = false
            while ti < t.count {
                if t[ti] == c {
                    var bonus = 10
                    if ti == prev + 1 { bonus += 15 }
                    if isBoundary(t, ti) { bonus += 30 }
                    s += bonus
                    prev = ti
                    ti += 1
                    found = true
                    break
                }
                ti += 1
            }
            if !found { return nil }
        }
        return s
    }

    private static func isBoundary(_ t: [Character], _ i: Int) -> Bool {
        i == 0 || !(t[i - 1].isLetter || t[i - 1].isNumber)
    }

    private static func firstIndex(of q: [Character], in t: [Character]) -> Int? {
        let last = t.count - q.count
        guard last >= 0 else { return nil }
        for i in 0...last where t[i] == q[0] {
            var ok = true
            for j in 1..<q.count where t[i + j] != q[j] { ok = false; break }
            if ok { return i }
        }
        return nil
    }
}
