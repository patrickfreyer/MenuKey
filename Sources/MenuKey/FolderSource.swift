import AppKit

/// Folder jumping: zoxide's frecency database first, Spotlight folder names as a fallback.
/// Every jump is fed back with `zoxide add`, so `z` in the terminal learns too.
enum FolderSource {
    static let zoxide: String? = {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin/zoxide", "/usr/local/bin/zoxide", "\(home)/.cargo/bin/zoxide",
                "\(home)/.local/bin/zoxide", "/usr/bin/zoxide"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    private static let home = NSHomeDirectory()

    /// Off main thread. `tokens` empty = top frecent folders.
    static func search(tokens: [String], limit: Int = 30) -> [SearchItem] {
        var paths: [String] = []
        var seen = Set<String>()
        func add(_ p: String) {
            guard seen.insert(p).inserted, FileManager.default.fileExists(atPath: p) else { return }
            paths.append(p)
        }

        if let zoxide {
            let out = run(zoxide, ["query", "--list", "--"] + tokens, limitLines: limit)
            out.forEach(add)
        }
        if paths.count < limit, let last = tokens.last, last.count >= 2 {
            let escaped = last.replacingOccurrences(of: "'", with: "")
            let query = "kMDItemContentType == 'public.folder' && kMDItemFSName == '*\(escaped)*'cd"
            let others = tokens.dropLast().map { SearchItem.normalize($0) }
            let needle = SearchItem.normalize(last)
            let hits = run("/usr/bin/mdfind", ["-onlyin", home, query], limitLines: 600)
                .filter { p in !isNoise(p) && others.allSatisfy { SearchItem.normalize(p).contains($0) } }
            // Name starts with the word > word-start inside the name > anywhere; then shallower paths.
            func rank(_ p: String) -> (Int, Int, Int) {
                let name = SearchItem.normalize((p as NSString).lastPathComponent)
                let fit = name.hasPrefix(needle) ? 0
                    : name.range(of: needle).map { r in
                        r.lowerBound == name.startIndex || !name[name.index(before: r.lowerBound)].isLetter ? 1 : 2 } ?? 3
                return (fit, p.filter { $0 == "/" }.count, p.count)
            }
            for p in hits.sorted(by: { rank($0) < rank($1) }) { add(p) }
        }

        // zoxide hits keep their frecency order; Spotlight hits follow.
        return paths.prefix(200).enumerated().map { i, p in
            let url = URL(fileURLWithPath: p)
            return SearchItem(
                id: "f\(i)-\(p)",
                kind: .folder,
                title: url.lastPathComponent.isEmpty ? p : url.lastPathComponent,
                subtitle: abbreviate(url.deletingLastPathComponent().path),
                icon: NSWorkspace.shared.icon(forFile: p),
                action: .folder(url),
                frecencyKey: "folder|\(p)",
                order: i
            )
        }
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
        let bad = ["/Library/", "/.", "node_modules", "/.build", "/build/", "/DerivedData/", ".app/", "/Pods/", "/venv/", "/.venv/", "/Caches/"]
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
