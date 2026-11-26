import Foundation

/// Fuzzy matcher: substring hits beat scattered subsequence hits, word-start
/// hits beat mid-word hits, titles beat subtitles. Frecency and learned
/// queries are added on top.
@MainActor
enum Matcher {
    struct Scored {
        let item: SearchItem
        let score: Int
        let strong: Bool    // every query word appears as a contiguous substring
    }

    static func tokens(_ query: String) -> [[Character]] {
        SearchItem.normalize(query).split(whereSeparator: { $0.isWhitespace }).map { Array($0) }
    }

    static func rank(_ items: [SearchItem], query: String, kindOffsets: Bool = false) -> [Scored] {
        let toks = tokens(query)
        let q = toks.map { String($0) }.joined(separator: " ")
        let frecency = Frecency.shared

        if toks.isEmpty {
            return items
                .map { Scored(item: $0, score: Int(frecency.score($0.frecencyKey) * 10), strong: false) }
                .sorted { $0.score != $1.score ? $0.score > $1.score : $0.item.order < $1.item.order }
        }

        var out: [Scored] = []
        out.reserveCapacity(items.count)
        outer: for item in items {
            var total = 0
            var strong = true
            for t in toks {
                let titleScore = score(t, item.titleKey).map { $0 * 2 }
                let subScore = score(t, item.subtitleKey)
                guard let best = [titleScore, subScore].compactMap({ $0 }).max() else { continue outer }
                if best < 800 { strong = false }
                total += best
            }
            let f = frecency.score(item.frecencyKey)
            if f > 0 { total += min(Int(log2(1 + f) * 150), 900) }
            if frecency.learned(item.frecencyKey, query: q) { total += 1200 }
            total -= item.titleKey.count
            if kindOffsets { total += offset(item.kind) }
            out.append(Scored(item: item, score: total, strong: strong))
        }
        return out.sorted { $0.score != $1.score ? $0.score > $1.score : $0.item.order < $1.item.order }
    }

    private static func offset(_ kind: ItemKind) -> Int {
        switch kind {
        case .menu: return 0
        case .window: return -150
        case .menuExtra: return -250
        case .folder: return -400
        case .file: return -450
        }
    }

    nonisolated static func score(_ q: [Character], _ t: [Character]) -> Int? {
        guard !q.isEmpty else { return 0 }
        guard q.count <= t.count else { return nil }

        if let idx = firstIndex(of: q, in: t) {
            var s = 1000 - idx
            if idx == 0 { s += 500 } else if isBoundary(t, idx) { s += 300 }
            return s
        }

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

    /// Character offsets in `title` to highlight for this query.
    nonisolated static func highlights(query: String, title: String) -> Set<Int> {
        let key = Array(SearchItem.normalize(title))
        guard key.count == title.count else { return [] }
        var hits = Set<Int>()
        for t in SearchItem.normalize(query).split(whereSeparator: { $0.isWhitespace }).map({ Array($0) }) {
            if let idx = firstIndex(of: t, in: key) {
                hits.formUnion(idx..<(idx + t.count))
                continue
            }
            var ti = 0, local: [Int] = []
            for c in t {
                while ti < key.count, key[ti] != c { ti += 1 }
                guard ti < key.count else { local = []; break }
                local.append(ti)
                ti += 1
            }
            hits.formUnion(local)
        }
        return hits
    }

    nonisolated private static func isBoundary(_ t: [Character], _ i: Int) -> Bool {
        i == 0 || !(t[i - 1].isLetter || t[i - 1].isNumber)
    }

    nonisolated private static func firstIndex(of q: [Character], in t: [Character]) -> Int? {
        let last = t.count - q.count
        guard last >= 0, !q.isEmpty else { return nil }
        for i in 0...last where t[i] == q[0] {
            var ok = true
            for j in 1..<q.count where t[i + j] != q[j] { ok = false; break }
            if ok { return i }
        }
        return nil
    }

    // MARK: - Phrase matching for plain-English suggestions

    private static let stopwords: Set<String> = ["the", "a", "an", "to", "of", "and", "for", "with", "as", "this", "my"]

    /// Items whose words best cover one of the suggested command phrases.
    static func phraseMatches(_ phrases: [String], in items: [SearchItem], limit: Int = 6) -> [SearchItem] {
        var best: [String: (SearchItem, Double)] = [:]
        let menuNames = Set(MenuScanner.topLevelTitles(items).map { SearchItem.normalize($0) })
        let phrases = phrases.filter { !menuNames.contains(SearchItem.normalize($0)) }
        for (rank, phrase) in phrases.enumerated() {
            let words = words(phrase)
            guard !words.isEmpty else { continue }
            for item in items {
                let titleWords = self.words(item.title)
                let pathWords = self.words(item.subtitle)
                var hit = 0.0
                for w in words {
                    if titleWords.contains(where: { $0.hasPrefix(w) || w.hasPrefix($0) && $0.count >= 4 }) { hit += 1 }
                    else if pathWords.contains(where: { $0.hasPrefix(w) }) { hit += 0.4 }
                }
                var s = hit / Double(words.count)
                if SearchItem.normalize(item.title).replacingOccurrences(of: "…", with: "") ==
                    SearchItem.normalize(phrase).replacingOccurrences(of: "…", with: "") { s += 1 }
                s -= Double(rank) * 0.03
                guard s >= 0.6 else { continue }
                if s > best[item.id]?.1 ?? 0 { best[item.id] = (item, s) }
            }
        }
        return best.values.sorted { $0.1 > $1.1 }.prefix(limit).map {
            var item = $0.0
            item.suggested = true
            return item
        }
    }

    private static func words(_ s: String) -> [String] {
        SearchItem.normalize(s)
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
    }
}
