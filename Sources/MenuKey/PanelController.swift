import AppKit
import ApplicationServices
import SwiftUI

/// Borderless, non-activating panel: it takes keyboard focus while the
/// target app stays frontmost, so its menus remain live and pressable.
final class SearchPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.headerHeight),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum Usage {
    private static let key = "usage"

    static func counts(for bundleID: String) -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: key)?[bundleID] as? [String: Int]) ?? [:]
    }

    static func bump(_ entry: MenuEntry, bundleID: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        var app = (all[bundleID] as? [String: Int]) ?? [:]
        app[entry.usageKey, default: 0] += 1
        all[bundleID] = app
        UserDefaults.standard.set(all, forKey: key)
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel = SearchPanel()
    private let model = SearchModel()
    private var keyMonitor: Any?
    private var scanToken = 0
    private var topY: CGFloat = 0

    override init() {
        super.init()
        let host = NSHostingView(rootView: SearchView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        panel.delegate = self
        model.onExecute = { [weak self] in self?.execute($0) }
        model.onLayoutChange = { [weak self] in self?.relayout() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        guard AXIsProcessTrusted() else {
            Permissions.requestAccessibility()
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        model.begin(app: app)
        placeOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
        model.focusTick += 1
        installKeyMonitor()

        scanToken += 1
        let token = scanToken
        let pid = app.processIdentifier
        let includeApple = Settings.includeAppleMenu
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = MenuScanner.scan(pid: pid, includeAppleMenu: includeApple)
            DispatchQueue.main.async {
                guard let self, token == self.scanToken, self.panel.isVisible else { return }
                self.model.load(entries)
            }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        scanToken += 1
        panel.orderOut(nil)
        removeKeyMonitor()
        model.reset()
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    private func execute(_ entry: MenuEntry) {
        let bundleID = model.bundleID
        hide()
        Usage.bump(entry, bundleID: bundleID)
        // AXPress can block until a modal dialog the item opens is dismissed,
        // so never run it on the main thread.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            AXUIElementPerformAction(entry.element, kAXPressAction as CFString)
        }
    }

    // MARK: - Layout

    private func placeOnActiveScreen() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        topY = vf.maxY - vf.height * 0.22
        let x = vf.midX - Layout.width / 2
        panel.setFrame(NSRect(x: x, y: topY - model.height, width: Layout.width, height: model.height), display: false)
    }

    private func relayout() {
        let h = model.height
        var f = panel.frame
        guard abs(f.height - h) > 0.5 else { return }
        f.origin.y = topY - h
        f.size.height = h
        panel.setFrame(f, display: true)
        panel.invalidateShadow()
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let ctrl = event.modifierFlags.contains(.control)
            switch (event.keyCode, ctrl, event.charactersIgnoringModifiers) {
            case (125, _, _), (_, true, "n"), (_, true, "j"): self.model.move(1); return nil
            case (126, _, _), (_, true, "p"), (_, true, "k"): self.model.move(-1); return nil
            case (121, _, _): self.model.move(Layout.maxVisibleRows); return nil   // page down
            case (116, _, _): self.model.move(-Layout.maxVisibleRows); return nil  // page up
            case (36, _, _), (76, _, _): self.model.executeSelected(); return nil
            case (53, _, _): self.hide(); return nil
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
