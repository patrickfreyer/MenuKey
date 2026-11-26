import AppKit
import UniformTypeIdentifiers

/// File and folder search: zoxide's frecency database first, then Spotlight.
/// Every folder jump is fed back with `zoxide add`, so `z` in the terminal learns too.
enum FolderSource {
    static let zoxide: String? = {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin/zoxide", "/usr/local/bin/zoxide", "\(home)/.cargo/bin/zoxide",
                "\(home)/.local/bin/zoxide", "/usr/bin/zoxide"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    private static let home = NSHomeDirectory()

    private struct Candidate {
        var isDir: Bool
        var lastUsed: Date?
        var zoxideRank: Int?
        var contentType: String = ""
    }

    /// Files and folders matching `tokens`, best first. Off main thread.
    /// - zoxide's folders come first (it already knows where you go),
    /// - then Spotlight hits ranked by how well the name matches and when you last opened them.
    /// `foldersOnly` is the `z ` mode. Empty `tokens` = frecent folders plus recently opened files.
    static func search(tokens: [String], foldersOnly: Bool = false, limit: Int = 40) -> [SearchItem] {
        var cands: [String: Candidate] = [:]

        if let zoxide {
            // zoxide can hold folders that were deleted since; Spotlight hits are always current.
            for (i, p) in run(zoxide, ["query", "--list", "--"] + tokens, limitLines: 30).enumerated()
            where FileManager.default.fileExists(atPath: p) {
                cands[p] = Candidate(isDir: true, lastUsed: nil, zoxideRank: i)
            }
        }

        var query: String?
        if let last = tokens.last {
            if last.count >= 2 {
                let escaped = last.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\\", with: "")
                query = "kMDItemFSName == '*\(escaped)*'cd" + (foldersOnly ? " && kMDItemContentType == 'public.folder'" : "")
            }
        } else if !foldersOnly {
            query = "kMDItemLastUsedDate >= $time.today(-7) && kMDItemContentType != 'public.folder'"
        }
        if let query {
            let others = tokens.dropLast().map { SearchItem.normalize($0) }
            let attrs = ["-attr", "kMDItemLastUsedDate", "-attr", "kMDItemContentType"]
            let lines = run("/usr/bin/mdfind", ["-onlyin", home] + attrs + [query], limitLines: 1500)
            for line in lines {
                guard let hit = parse(line), !isNoise(hit.path), cands[hit.path] == nil,
                      others.allSatisfy({ SearchItem.normalize(hit.path).contains($0) }) else { continue }
                cands[hit.path] = Candidate(isDir: hit.isDir, lastUsed: hit.lastUsed, zoxideRank: nil, contentType: hit.type)
            }
        }

        let needle = tokens.last.map { SearchItem.normalize($0) } ?? ""
        let now = Date()
        func score(_ path: String, _ c: Candidate) -> Double {
            var s = 0.0
            if let z = c.zoxideRank { s += 600 - Double(z) * 15 }
            let name = SearchItem.normalize((path as NSString).lastPathComponent)
            if !needle.isEmpty {
                if name.hasPrefix(needle) { s += 300 }
                else if let r = name.range(of: needle) {
                    s += (r.lowerBound == name.startIndex || !name[name.index(before: r.lowerBound)].isLetter) ? 200 : 100
                }
            }
            if let used = c.lastUsed {
                let age = now.timeIntervalSince(used)
                s += age < 86_400 ? 260 : age < 604_800 ? 190 : age < 2_592_000 ? 120 : age < 31_536_000 ? 50 : 0
            }
            if c.isDir { s += 40 }                                   // folders are usually what people jump to
            s -= Double(path.filter { $0 == "/" }.count) * 6        // shallower first
            return s
        }

        // No file-system calls on Spotlight hits: Desktop, Documents and Downloads are
        // privacy-protected, and touching them would prompt for access.
        let ranked = cands
            .map { (path: $0.key, cand: $0.value, score: score($0.key, $0.value)) }
            .sorted { $0.score > $1.score }
            .prefix(limit)

        return ranked.enumerated().map { i, r in
            let url = URL(fileURLWithPath: r.path)
            return SearchItem(
                id: "f\(i)-\(r.path)",
                kind: r.cand.isDir ? .folder : .file,
                title: url.lastPathComponent.isEmpty ? r.path : url.lastPathComponent,
                subtitle: abbreviate(url.deletingLastPathComponent().path),
                icon: icon(for: r.cand),
                action: r.cand.isDir ? .folder(url) : .file(url),
                frecencyKey: (r.cand.isDir ? "folder|" : "file|") + r.path,
                order: i
            )
        }
    }

    /// One line of `mdfind -attr kMDItemLastUsedDate -attr kMDItemContentType`:
    /// `<path>   kMDItemLastUsedDate = 2026-11-20 10:00:00 +0000   kMDItemContentType = public.folder`
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()

    private static func icon(for c: Candidate) -> NSImage {
        if c.isDir { return NSWorkspace.shared.icon(for: .folder) }
        return NSWorkspace.shared.icon(for: UTType(c.contentType) ?? .data)
    }

    private static func parse(_ line: String) -> (path: String, lastUsed: Date?, isDir: Bool, type: String)? {
        guard let r = line.range(of: "   kMDItemLastUsedDate = ") else { return nil }
        let path = String(line[..<r.lowerBound])
        let rest = line[r.upperBound...]
        let parts = rest.components(separatedBy: "   kMDItemContentType = ")
        let date = parts.first.flatMap { $0 == "(null)" ? nil : dateFormatter.date(from: $0) }
        let type = parts.count > 1 ? parts[1] : ""
        return (path, date, type == "public.folder", type)
    }

    // MARK: Protected folders

    /// Spotlight hides Desktop, Documents and Downloads from apps macOS hasn't let in.
    static let protectedFolders = ["Desktop", "Documents", "Downloads"]

    static var askedForFolderAccess: Bool {
        get { UserDefaults.standard.bool(forKey: "askedFolderAccess") }
        set { UserDefaults.standard.set(newValue, forKey: "askedFolderAccess") }
    }

    /// Reading each folder once makes macOS show its "allow access" prompt.
    static func requestFolderAccess() {
        askedForFolderAccess = true
        DispatchQueue.global(qos: .userInitiated).async {
            for name in protectedFolders {
                _ = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/\(name)")
            }
        }
    }

    static var accessRow: SearchItem {
        SearchItem(id: "grant-folder-access", kind: .file,
                   title: "Search your Desktop, Documents and Downloads",
                   subtitle: "Press Return, then allow access when macOS asks for each folder",
                   icon: NSImage(systemSymbolName: "lock.open.fill", accessibilityDescription: nil),
                   action: .grantFolderAccess, frecencyKey: "grant-folder-access", order: -1)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ url: URL, inTerminal: Bool) {
        if inTerminal, let term = Terminals.selectedURL {
            NSWorkspace.shared.open([url], withApplicationAt: term, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
        if let zoxide {
            DispatchQueue.global(qos: .utility).async { _ = run(zoxide, ["add", "--", url.path], limitLines: 1) }
        }
    }

    static func abbreviate(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private static func isNoise(_ p: String) -> Bool {
        if p.contains("/Library/Mobile Documents/com~apple~CloudDocs/") { return false }   // iCloud Drive
        let bad = ["/Library/", "/.", "node_modules", "/.build", "/build/", "/DerivedData/", ".app/", "/Pods/", "/venv/", "/.venv/", "/Caches/", "/__pycache__/", "/.git/", "/site-packages/"]
        return bad.contains { p.contains($0) } || p.hasSuffix(".app") || p.hasSuffix(".bundle")
    }

    @discardableResult
    static func run(_ exe: String, _ args: [String], limitLines: Int) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        var data = Data()
        let handle = pipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.filter({ $0 == 10 }).count >= limitLines { p.terminate(); break }
        }
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n").prefix(limitLines).map(String.init)
    }
}

enum Terminals {
    static let candidates: [(name: String, bundleID: String)] = [
        ("Terminal", "com.apple.Terminal"),
        ("iTerm", "com.googlecode.iterm2"),
        ("Ghostty", "com.mitchellh.ghostty"),
        ("Warp", "dev.warp.Warp-Stable"),
        ("WezTerm", "com.github.wez.wezterm"),
        ("kitty", "net.kovidgoyal.kitty"),
        ("Alacritty", "org.alacritty"),
        ("Hyper", "co.zeit.hyper"),
    ]

    static var installed: [(name: String, bundleID: String)] {
        candidates.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    static var selectedBundleID: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: "terminal"),
               NSWorkspace.shared.urlForApplication(withBundleIdentifier: saved) != nil { return saved }
            // Default: the first third-party terminal you have, else Terminal.
            return installed.first(where: { $0.bundleID != "com.apple.Terminal" })?.bundleID ?? "com.apple.Terminal"
        }
        set { UserDefaults.standard.set(newValue, forKey: "terminal") }
    }

    static var selectedName: String {
        candidates.first { $0.bundleID == selectedBundleID }?.name ?? "Terminal"
    }

    static var selectedURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: selectedBundleID)
    }

    static func isTerminal(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return candidates.contains { $0.bundleID == bundleID }
    }
}
