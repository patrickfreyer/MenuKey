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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "filemenu.and.selection", accessibilityDescription: "MenuKey")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        HotKey.onPress = { [weak self] in self?.panel.toggle() }
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
        menu.addItem(NSMenuItem(title: "Quit MenuKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
