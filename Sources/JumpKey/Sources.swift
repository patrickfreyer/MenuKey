import AppKit
import ApplicationServices

// MARK: - Windows

enum WindowSource {
    /// Windows of every regular app on the current Space (plus minimized ones). Off main thread.
    static func scan(excluding ownPID: pid_t) -> [SearchItem] {
        var out: [SearchItem] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appEl, 0.25)
            let appName = app.localizedName ?? "App"
            let windows: [AXUIElement] = AX.attribute(appEl, kAXWindowsAttribute) ?? []
            for win in windows {
                let role = AX.string(win, kAXSubroleAttribute)
                guard role == kAXStandardWindowSubrole || role == kAXDialogSubrole || role.isEmpty else { continue }
                let title = AX.string(win, kAXTitleAttribute)
                let minimized: Bool = AX.attribute(win, kAXMinimizedAttribute) ?? false
                var wid: CGWindowID = 0
                _ = _AXUIElementGetWindow(win, &wid)
                out.append(SearchItem(
                    id: "w\(app.processIdentifier)-\(wid)-\(out.count)",
                    kind: .window,
                    title: title.isEmpty ? appName : title,
                    subtitle: minimized ? "\(appName) · minimized" : appName,
                    icon: app.icon,
                    windowID: wid == 0 ? nil : wid,
                    action: .window(app: appEl, window: win),
                    frecencyKey: "window|\(app.bundleIdentifier ?? appName)|\(title)",
                    order: out.count
                ))
            }
        }
        return out
    }

    static func focus(app: AXUIElement, window: AXUIElement) {
        if (AX.attribute(window, kAXMinimizedAttribute) as Bool?) == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

// MARK: - Menu bar icons

enum MenuExtraSource {
    /// macOS 27 hosts every status item in MenuBarAgent; older systems expose
    /// them per app through AXExtrasMenuBar. Off main thread.
    static func scan() -> [SearchItem] {
        if let agent = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.MenuBarAgent" }) {
            let items = scanAgent(pid: agent.processIdentifier)
            if !items.isEmpty { return items }
        }
        return scanPerApp()
    }

    private struct Found {
        var name: String
        var detail: String
        var element: AXUIElement
        var x: Int
        var owner: String?
    }

    private static func scanAgent(pid: pid_t) -> [SearchItem] {
        let agent = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(agent, 0.5)
        var found: [Found] = []
        var ownerByX: [Int: String] = [:]

        func position(_ el: AXUIElement) -> Int {
            guard let v: AXValue = AX.attribute(el, kAXPositionAttribute) else { return -1 }
            var p = CGPoint.zero
            AXValueGetValue(v, .cgPoint, &p)
            return Int(p.x.rounded())
        }

        func visit(_ el: AXUIElement, depth: Int, groupX: Int) {
            guard depth < 7 else { return }
            let role = AX.string(el, kAXRoleAttribute)
            if role == kAXApplicationRole {
                // Proxy of the owning app: remember its name for this slot, don't descend.
                let t = AX.string(el, kAXTitleAttribute)
                if !t.isEmpty { ownerByX[groupX] = t }
                return
            }
            let subrole = AX.string(el, kAXSubroleAttribute)
            if (role == kAXMenuBarItemRole && subrole == "AXMenuExtra") || role == kAXButtonRole {
                let title = AX.string(el, kAXTitleAttribute)
                let desc = AX.string(el, kAXDescriptionAttribute)
                let ident = AX.string(el, kAXIdentifierAttribute)
                var name = desc.isEmpty ? title : desc
                var detail = ""
                if ident.hasPrefix("com.apple.menuextra."), let comma = name.range(of: ", ") {
                    detail = String(name[comma.upperBound...])
                    name = String(name[..<comma.lowerBound])
                }
                if !title.isEmpty, !desc.isEmpty, title != desc, role == kAXButtonRole { name = title; detail = desc }
                if !name.isEmpty {
                    found.append(Found(name: name, detail: detail, element: el, x: groupX))
                }
                return
            }
            let x = role == kAXGroupRole && groupX < 0 ? position(el) : groupX
            for child in AX.children(el) { visit(child, depth: depth + 1, groupX: x) }
        }

        let windows: [AXUIElement] = AX.attribute(agent, kAXWindowsAttribute) ?? []
        for w in windows { visit(w, depth: 0, groupX: -1) }

        // Attach owner app names (e.g. a button labelled "Audio Waveform" belongs to Murmur).
        var seenX = Set<Int>()
        var result: [SearchItem] = []
        let running = NSWorkspace.shared.runningApplications
        let ownName = ProcessInfo.processInfo.processName
        for var f in found.sorted(by: { $0.x > $1.x }) {
            guard seenX.insert(f.x).inserted, f.name != ownName, f.name != "JumpKey" else { continue }
            // Only rename icons whose label isn't already an app name, and never
            // attribute them to Apple's hosting processes (Siri hosts Spotlight, etc.).
            let labelIsApp = running.contains { $0.localizedName == f.name }
            if !labelIsApp,
               let owner = ownerByX.first(where: { abs($0.key - f.x) <= 3 })?.value, owner != f.name,
               let ownerApp = running.first(where: { $0.localizedName == owner }),
               !(ownerApp.bundleIdentifier ?? "").hasPrefix("com.apple.") {
                if f.detail.isEmpty { f.detail = f.name }
                f.name = owner
            }
            let icon = running.first(where: { $0.localizedName == f.name })?.icon
                ?? NSImage(systemSymbolName: symbol(for: f.name), accessibilityDescription: nil)
            result.append(SearchItem(
                id: "x\(result.count)",
                kind: .menuExtra,
                title: f.name,
                subtitle: f.detail.isEmpty ? "Menu bar" : "Menu bar · \(f.detail)",
                icon: icon,
                action: .press(f.element),
                frecencyKey: "extra|\(f.name)",
                order: result.count
            ))
        }
        return result
    }

    private static func scanPerApp() -> [SearchItem] {
        var out: [SearchItem] = []
        for app in NSWorkspace.shared.runningApplications {
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(el, 0.05)
            guard let bar: AXUIElement = AX.attribute(el, kAXExtrasMenuBarAttribute) else { continue }
            for item in AX.children(bar) {
                let t = AX.string(item, kAXTitleAttribute)
                let d = AX.string(item, kAXDescriptionAttribute)
                let name = app.localizedName ?? (t.isEmpty ? d : t)
                out.append(SearchItem(id: "x\(out.count)", kind: .menuExtra, title: name,
                                      subtitle: "Menu bar", icon: app.icon, action: .press(item),
                                      frecencyKey: "extra|\(name)", order: out.count))
            }
        }
        return out
    }

    private static func symbol(for name: String) -> String {
        switch name.lowercased() {
        case let n where n.contains("wi"): return "wifi"
        case let n where n.contains("battery"): return "battery.75percent"
        case let n where n.contains("control"): return "switch.2"
        case let n where n.contains("clock"): return "clock"
        case let n where n.contains("spotlight") || n.contains("search"): return "magnifyingglass"
        case let n where n.contains("bluetooth"): return "bluetooth"
        case let n where n.contains("sound") || n.contains("volume"): return "speaker.wave.2"
        default: return "menubar.rectangle"
        }
    }
}
