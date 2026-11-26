import AppKit
@preconcurrency import ApplicationServices
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

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel = SearchPanel()
    private let model = SearchModel()
    private let preview = PreviewController()
    private var keyMonitor: Any?
    private var scanToken = 0
    private var topY: CGFloat = 0
    private var shownAt = Date.distantPast

    /// What ran last, for "press the shortcut twice to repeat".
    private var lastItem: SearchItem?
    private var lastBundleID: String?

    override init() {
        super.init()
        let host = NSHostingView(rootView: SearchView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        panel.delegate = self
        model.onExecute = { [weak self] item, alt in self?.perform(item, alternate: alt) }
        model.onLayoutChange = { [weak self] in self?.relayout() }
        model.onSelectionChange = { [weak self] in self?.updatePreview() }
    }

    func hotKeyPressed() {
        if panel.isVisible {
            // Second press right after opening = repeat the last command.
            if Date().timeIntervalSince(shownAt) < 0.4, lastItem != nil {
                hide()
                repeatLast()
            } else {
                hide()
            }
        } else {
            show()
        }
    }

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
        shownAt = Date()
        model.focusTick += 1
        installKeyMonitor()
        preview.beginSession()

        scanToken += 1
        let token = scanToken
        let pid = app.processIdentifier
        let bundleID = model.bundleID
        let includeApple = Settings.includeAppleMenu
        let ownPID = ProcessInfo.processInfo.processIdentifier

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = MenuScanner.scan(pid: pid, bundleID: bundleID, includeAppleMenu: includeApple)
            DispatchQueue.main.async {
                guard let self, token == self.scanToken else { return }
                self.model.setMenus(items)
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = WindowSource.scan(excluding: ownPID)
            DispatchQueue.main.async {
                guard let self, token == self.scanToken else { return }
                self.model.setWindows(items)
            }
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let items = MenuExtraSource.scan()
            DispatchQueue.main.async {
                guard let self, token == self.scanToken else { return }
                self.model.setExtras(items)
            }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        scanToken += 1
        preview.hide()
        panel.orderOut(nil)
        removeKeyMonitor()
        model.reset()
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    // MARK: - Actions

    private func perform(_ item: SearchItem, alternate: Bool) {
        let query = model.trimmedQuery
        let bundleID = model.bundleID
        let targetIsTerminal = model.targetIsTerminal
        hide()
        if case .grantFolderAccess = item.action {
            run(item, alternate: alternate, targetIsTerminal: targetIsTerminal)
            return
        }
        Frecency.shared.record(item.frecencyKey, query: query)
        lastItem = item
        lastBundleID = bundleID
        run(item, alternate: alternate, targetIsTerminal: targetIsTerminal)
    }

    private func run(_ item: SearchItem, alternate: Bool, targetIsTerminal: Bool) {
        switch item.action {
        case .press(let element):
            // AXPress can block until a dialog the item opens is dismissed,
            // so never run it on the main thread.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
                AXUIElementPerformAction(element, kAXPressAction as CFString)
            }
        case .window(let app, let window):
            DispatchQueue.global(qos: .userInitiated).async { WindowSource.focus(app: app, window: window) }
        case .folder(let url):
            // In a terminal, Return opens a terminal window; elsewhere it opens Finder. ⌘Return flips it.
            FolderSource.open(url, inTerminal: targetIsTerminal != alternate)
        case .grantFolderAccess:
            FolderSource.requestFolderAccess()
        case .file(let url):
            // Return opens the file in its app; ⌘Return shows it in Finder.
            if alternate { FolderSource.reveal(url) } else { NSWorkspace.shared.open(url) }
        }
    }

    private func repeatLast() {
        guard let item = lastItem else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let targetIsTerminal = Terminals.isTerminal(front?.bundleIdentifier)
        guard item.kind == .menu else {
            run(item, alternate: false, targetIsTerminal: targetIsTerminal)
            return
        }
        // Menu items belong to one app; re-find it there in case the menu was rebuilt.
        guard let front, front.bundleIdentifier == lastBundleID else { NSSound.beep(); return }
        let pid = front.processIdentifier
        let bundleID = front.bundleIdentifier ?? ""
        let key = item.frecencyKey
        DispatchQueue.global(qos: .userInitiated).async {
            let items = MenuScanner.scan(pid: pid, bundleID: bundleID, includeAppleMenu: true)
            guard let match = items.first(where: { $0.frecencyKey == key }),
                  case .press(let element) = match.action else {
                DispatchQueue.main.async { NSSound.beep() }
                return
            }
            AXUIElementPerformAction(element, kAXPressAction as CFString)
            DispatchQueue.main.async { Frecency.shared.record(key, query: "") }
        }
    }

    // MARK: - Layout

    private func placeOnActiveScreen() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        topY = vf.maxY - vf.height * 0.2
        let x = vf.midX - Layout.width / 2
        panel.setFrame(NSRect(x: x, y: topY - model.height, width: Layout.width, height: model.height), display: false)
    }

    private func relayout() {
        let h = model.height
        var f = panel.frame
        guard abs(f.height - h) > 0.5 else { updatePreview(); return }
        f.origin.y = topY - h
        f.size.height = h
        panel.setFrame(f, display: true)
        panel.invalidateShadow()
        updatePreview()
    }

    private func updatePreview() {
        guard panel.isVisible else { return }
        preview.show(for: model.selected, beside: panel)
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let ctrl = flags.contains(.control)
            switch (event.keyCode, ctrl, event.charactersIgnoringModifiers) {
            case (125, _, _), (_, true, "n"), (_, true, "j"): self.model.move(1); return nil
            case (126, _, _), (_, true, "p"), (_, true, "k"): self.model.move(-1); return nil
            case (121, _, _): self.model.move(Layout.maxVisibleRows); return nil
            case (116, _, _): self.model.move(-Layout.maxVisibleRows); return nil
            case (48, _, _): self.model.cycleScope(flags.contains(.shift) ? -1 : 1); return nil   // Tab
            case (36, _, _), (76, _, _): self.model.executeSelected(alternate: flags.contains(.command)); return nil
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
