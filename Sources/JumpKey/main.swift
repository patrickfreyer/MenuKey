import AppKit

// Test modes, no UI:
//   JumpKey --dump <app> [query]     menu items JumpKey sees (ranked if a query is given)
//   JumpKey --windows [query]        open windows
//   JumpKey --extras                 menu bar icons
//   JumpKey --files [words…]         file and folder search (zoxide + Spotlight)
//   JumpKey --folders [words…]       folders only (the "z " mode)
//   JumpKey --ask <app> <request>    plain-English fallback
let args = CommandLine.arguments

@MainActor func printItems(_ items: [SearchItem], _ query: String?, limit: Int = 40) {
    let list = query.map { Matcher.rank(items, query: $0).map(\.item) } ?? items
    for e in list.prefix(limit) {
        print("  \(e.checked ? "✓ " : "")\(e.title)  —  \(e.subtitle)  \(e.shortcut)")
    }
}

@MainActor func runCLI() -> Bool {
    guard args.count >= 2 else { return false }
    let start = Date()
    func ms() -> Int { Int(Date().timeIntervalSince(start) * 1000) }
    func app(_ name: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.lowercased() == name.lowercased() || $0.bundleIdentifier?.lowercased() == name.lowercased()
        }
    }

    switch args[1] {
    case "--dump" where args.count >= 3:
        guard let a = app(args[2]) else { print("No running app named \(args[2])"); exit(1) }
        let items = MenuScanner.scan(pid: a.processIdentifier, bundleID: a.bundleIdentifier ?? "", includeAppleMenu: false)
        print("\(items.count) items in \(ms()) ms (AX trusted: \(AXIsProcessTrusted()))")
        printItems(items, args.count >= 4 ? args[3] : nil)
    case "--windows":
        let items = WindowSource.scan(excluding: ProcessInfo.processInfo.processIdentifier)
        print("\(items.count) windows in \(ms()) ms")
        printItems(items, args.count >= 3 ? args[2] : nil)
    case "--extras":
        let items = MenuExtraSource.scan()
        print("\(items.count) menu bar icons in \(ms()) ms")
        printItems(items, nil)
    case "--files", "--folders":
        let items = FolderSource.search(tokens: Array(args.dropFirst(2)), foldersOnly: args[1] == "--folders")
        print("\(items.count) results in \(ms()) ms (zoxide: \(FolderSource.zoxide ?? "none"))")
        printItems(items, nil, limit: 15)
    case "--ask" where args.count >= 4:
        guard let a = app(args[2]) else { print("No running app named \(args[2])"); exit(1) }
        let items = MenuScanner.scan(pid: a.processIdentifier, bundleID: a.bundleIdentifier ?? "", includeAppleMenu: false)
        let request = args[3...].joined(separator: " ")
        print("AI available: \(Assistant.isAvailable) \(Assistant.unavailableReason)")
        let sem = DispatchSemaphore(value: 0)
        var commands: [String] = []
        Task.detached {
            commands = await Assistant.guessCommands(for: request, app: a.localizedName ?? "", menus: MenuScanner.topLevelTitles(items))
            sem.signal()
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.current.run(until: Date() + 0.05) }
        print("model said (\(ms()) ms): \(commands)")
        printItems(Matcher.phraseMatches(commands, in: items), nil)
    default:
        return false
    }
    return true
}

MainActor.assumeIsolated {
    if runCLI() { exit(0) }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
