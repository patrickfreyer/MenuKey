import AppKit

// `MenuKey --dump <app name>` prints the menu items MenuKey sees (for testing).
let args = CommandLine.arguments
if args.count >= 3, args[1] == "--dump" {
    let name = args[2].lowercased()
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.localizedName?.lowercased() == name || $0.bundleIdentifier?.lowercased() == name
    }) else {
        print("No running app named \(args[2])"); exit(1)
    }
    let start = Date()
    let entries = MenuScanner.scan(pid: app.processIdentifier, includeAppleMenu: false)
    print("\(entries.count) items in \(Int(Date().timeIntervalSince(start) * 1000)) ms (AX trusted: \(AXIsProcessTrusted()))")
    if args.count >= 4 {
        for e in Matcher.rank(entries, query: args[3], usage: [:]).prefix(10) {
            print("  \(e.title)  —  \(e.pathString)  \(e.shortcut)")
        }
    } else {
        for e in entries.prefix(40) { print("  \(e.pathString) › \(e.title)  \(e.shortcut)") }
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
