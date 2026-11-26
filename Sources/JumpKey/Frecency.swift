import Foundation

/// zoxide-style frecency: every use adds 1 to an item's rank, the score is the
/// rank weighted by how recently it was used, and old ranks decay once the
/// total grows past a cap. On top of that, JumpKey remembers which queries led
/// to each item, so "t" can come to mean "New Tab".
@MainActor
final class Frecency {
    static let shared = Frecency()

    struct Entry: Codable {
        var rank: Double
        var last: Date
        var queries: [String]
    }

    private var entries: [String: Entry] = [:]
    private let url: URL
    private let maxTotal = 10_000.0

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JumpKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("frecency.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    /// zoxide's weighting: ×4 within the hour, ×2 within the day, ×½ within the week, ×¼ after.
    func score(_ key: String, now: Date = Date()) -> Double {
        guard let e = entries[key] else { return 0 }
        let age = now.timeIntervalSince(e.last)
        let factor = age < 3600 ? 4.0 : age < 86_400 ? 2.0 : age < 604_800 ? 0.5 : 0.25
        return e.rank * factor
    }

    /// True if this item was picked before with a query that starts like this one.
    func learned(_ key: String, query: String) -> Bool {
        guard !query.isEmpty, let e = entries[key] else { return false }
        return e.queries.contains { $0.hasPrefix(query) || (query.hasPrefix($0) && $0.count >= 2) }
    }

    func record(_ key: String, query: String) {
        var e = entries[key] ?? Entry(rank: 0, last: Date(), queries: [])
        e.rank += 1
        e.last = Date()
        let q = SearchItem.normalize(query.trimmingCharacters(in: .whitespaces))
        if !q.isEmpty {
            e.queries.removeAll { $0 == q }
            e.queries.insert(q, at: 0)
            e.queries = Array(e.queries.prefix(8))
        }
        entries[key] = e
        age()
        save()
    }

    private func age() {
        let total = entries.values.reduce(0) { $0 + $1.rank }
        guard total > maxTotal else { return }
        let k = 0.9 * maxTotal / total
        for (key, var e) in entries {
            e.rank *= k
            if e.rank < 1 { entries[key] = nil } else { entries[key] = e }
        }
    }

    private func save() {
        let snapshot = entries
        let url = url
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }
}
