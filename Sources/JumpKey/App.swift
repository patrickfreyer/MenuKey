import AppKit
import ApplicationServices
import ServiceManagement

enum Settings {
    static var hotKeyIndex: Int {
        get { min(max(UserDefaults.standard.integer(forKey: "hotKeyIndex"), 0), HotKeyPresets.all.count - 1) }
        set { UserDefaults.standard.set(newValue, forKey: "hotKeyIndex") }
    }
    static var includeAppleMenu: Bool {
        get { UserDefaults.standard.bool(forKey: "includeAppleMenu") }
        set { UserDefaults.standard.set(newValue, forKey: "includeAppleMenu") }
    }
    static var plainEnglish: Bool {
        get { UserDefaults.standard.object(forKey: "plainEnglish") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "plainEnglish") }
    }
    static var windowPreviews: Bool {
        get { UserDefaults.standard.bool(forKey: "windowPreviews") }
        set { UserDefaults.standard.set(newValue, forKey: "windowPreviews") }
    }
}

enum Permissions {
    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let panel = PanelController()
    private let hotKey = HotKey()
    private var hotKeyFailed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Migration.fromMenuKeyIfNeeded()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "filemenu.and.selection", accessibilityDescription: "JumpKey")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        HotKey.onPress = { [weak self] in self?.panel.hotKeyPressed() }
        installEditMenu()
        applyHotKey()

        if !AXIsProcessTrusted() { Permissions.requestAccessibility() }
        enableLaunchAtLoginOnFirstRun()
    }

    /// A menu-search utility is only useful if it's always there, so turn on
    /// launch-at-login once; afterwards the menu toggle is the user's choice.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "didSetUpLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        UserDefaults.standard.set(SMAppService.mainApp.status == .enabled, forKey: key)
    }

    /// Accessory apps have no menu bar, so text-editing shortcuts (⌘A, ⌘C, ⌘V, ⌘Z)
    /// need a main menu to route through, even an invisible one.
    private func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func applyHotKey() {
        hotKeyFailed = !hotKey.register(HotKeyPresets.all[Settings.hotKeyIndex])
    }

    // Rebuild the status menu each time it opens so it reflects current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let preset = HotKeyPresets.all[Settings.hotKeyIndex]

        let search = NSMenuItem(title: "Search Menus   \(preset.label)", action: #selector(searchFromMenu), keyEquivalent: "")
        search.target = self
        menu.addItem(search)
        if hotKeyFailed {
            let warn = NSMenuItem(title: "⚠︎ \(preset.label) is taken by another app", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        let keys = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, p) in HotKeyPresets.all.enumerated() {
            let item = NSMenuItem(title: p.note.map { "\(p.label)  (\($0))" } ?? p.label,
                                  action: #selector(pickHotKey(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = i == Settings.hotKeyIndex ? .on : .off
            sub.addItem(item)
        }
        keys.submenu = sub
        menu.addItem(keys)

        let apple = NSMenuItem(title: "Include Apple Menu", action: #selector(toggleApple), keyEquivalent: "")
        apple.target = self
        apple.state = Settings.includeAppleMenu ? .on : .off
        menu.addItem(apple)

        let terms = NSMenuItem(title: "Open Folders In", action: nil, keyEquivalent: "")
        let termMenu = NSMenu()
        for t in Terminals.installed {
            let item = NSMenuItem(title: t.name, action: #selector(pickTerminal(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = t.bundleID
            item.state = t.bundleID == Terminals.selectedBundleID ? .on : .off
            termMenu.addItem(item)
        }
        termMenu.addItem(.separator())
        let zinfo = NSMenuItem(title: FolderSource.zoxide == nil ? "zoxide not found, using Spotlight" : "Ranked by zoxide", action: nil, keyEquivalent: "")
        zinfo.isEnabled = false
        termMenu.addItem(zinfo)
        terms.submenu = termMenu
        menu.addItem(terms)

        let files = NSMenuItem(title: "Allow Searching Desktop, Documents & Downloads…", action: #selector(grantFolders), keyEquivalent: "")
        files.target = self
        menu.addItem(files)

        let previews = NSMenuItem(title: "Window Previews", action: #selector(togglePreviews), keyEquivalent: "")
        previews.target = self
        previews.state = Settings.windowPreviews ? .on : .off
        menu.addItem(previews)

        let ai = NSMenuItem(title: Assistant.isAvailable ? "Plain-English Search" : "Plain-English Search (\(Assistant.unavailableReason))",
                            action: Assistant.isAvailable ? #selector(togglePlainEnglish) : nil, keyEquivalent: "")
        ai.target = self
        ai.state = Settings.plainEnglish && Assistant.isAvailable ? .on : .off
        menu.addItem(ai)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if !AXIsProcessTrusted() {
            menu.addItem(.separator())
            let ax = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAX), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit JumpKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func searchFromMenu() {
        // Let the status menu close before the panel takes focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.panel.show() }
    }

    @objc private func pickHotKey(_ sender: NSMenuItem) {
        Settings.hotKeyIndex = sender.tag
        applyHotKey()
    }

    @objc private func toggleApple() { Settings.includeAppleMenu.toggle() }

    @objc private func pickTerminal(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { Terminals.selectedBundleID = id }
    }

    @objc private func grantFolders() { FolderSource.requestFolderAccess() }

    @objc private func togglePlainEnglish() { Settings.plainEnglish.toggle() }

    @objc private func togglePreviews() {
        Settings.windowPreviews.toggle()
        if Settings.windowPreviews && !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func grantAX() { Permissions.requestAccessibility() }
}
