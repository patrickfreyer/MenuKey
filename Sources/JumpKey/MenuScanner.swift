import AppKit
import ApplicationServices

/// Reads the frontmost app's menu bar.
enum MenuScanner {
    private static let maxDepth = 6
    private static let maxItems = 6000

    private static let itemAttributes = [
        kAXTitleAttribute,
        kAXEnabledAttribute,
        kAXMenuItemCmdCharAttribute,
        kAXMenuItemCmdModifiersAttribute,
        kAXMenuItemCmdGlyphAttribute,
        kAXChildrenAttribute,
        kAXMenuItemMarkCharAttribute,
    ] as CFArray

    /// Safe to call off the main thread.
    static func scan(pid: pid_t, bundleID: String, includeAppleMenu: Bool) -> [SearchItem] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.5)

        guard let bar: AXUIElement = AX.attribute(app, kAXMenuBarAttribute) else { return [] }
        var out: [SearchItem] = []
        for (index, top) in AX.children(bar).enumerated() {
            if index == 0 && !includeAppleMenu { continue }
            let title = AX.string(top, kAXTitleAttribute)
            guard !title.isEmpty, let menu = AX.children(top).first else { continue }
            walk(menu: menu, path: [title], depth: 1, bundleID: bundleID, into: &out)
        }
        return out
    }

    /// Top-level menu titles, used as context for the plain-English fallback.
    static func topLevelTitles(_ items: [SearchItem]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for item in items {
            let top = item.subtitle.components(separatedBy: " › ").first ?? ""
            if !top.isEmpty, seen.insert(top).inserted { out.append(top) }
        }
        return out
    }

    private static func walk(menu: AXUIElement, path: [String], depth: Int, bundleID: String, into out: inout [SearchItem]) {
        guard depth <= maxDepth, out.count < maxItems else { return }

        for item in AX.children(menu) {
            guard out.count < maxItems else { return }
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(item, itemAttributes, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
                  let values = raw as? [Any], values.count == 7 else { continue }

            let title = (values[0] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !title.isEmpty else { continue } // separators
            let enabled = (values[1] as? Bool) ?? false
            let children = (values[5] as? [AXUIElement]) ?? []

            if let submenu = children.first {
                walk(menu: submenu, path: path + [title], depth: depth + 1, bundleID: bundleID, into: &out)
                continue
            }
            guard enabled else { continue }

            let shortcut = formatShortcut(
                char: values[2] as? String,
                modifiers: (values[3] as? NSNumber)?.intValue ?? 0,
                glyph: (values[4] as? NSNumber)?.intValue
            )
            let mark = (values[6] as? String) ?? ""
            let fullPath = (path + [title]).joined(separator: "/")
            out.append(SearchItem(
                id: "m\(out.count)",
                kind: .menu,
                title: title,
                subtitle: path.joined(separator: " › "),
                shortcut: shortcut,
                checked: mark == "✓" || mark == "✔",
                action: .press(item),
                frecencyKey: "menu|\(bundleID)|\(fullPath)",
                order: out.count
            ))
        }
    }

    // MARK: - Shortcut formatting

    private static let glyphs: [Int: String] = [
        0x02: "⇥", 0x04: "⌅", 0x09: "␣", 0x0A: "⌦", 0x0B: "↩", 0x17: "⌫", 0x1B: "⎋",
        0x64: "←", 0x65: "→", 0x68: "↑", 0x6A: "↓", 0x62: "⇞", 0x6B: "⇟", 0x66: "↖", 0x67: "↘",
        0x6F: "F1", 0x70: "F2", 0x71: "F3", 0x72: "F4", 0x73: "F5", 0x74: "F6",
        0x75: "F7", 0x76: "F8", 0x77: "F9", 0x78: "F10", 0x79: "F11", 0x7A: "F12",
    ]

    private static let functionKeys: [Int: String] = {
        var m: [Int: String] = [0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→",
                                0xF728: "⌦", 0xF729: "↖", 0xF72B: "↘", 0xF72C: "⇞", 0xF72D: "⇟"]
        for i in 1...20 { m[0xF703 + i] = "F\(i)" }
        return m
    }()

    static func formatShortcut(char: String?, modifiers: Int, glyph: Int?) -> String {
        var key = char ?? ""
        // NSFunctionKey characters (arrows, F-keys, Home/End…) live in U+F700–F8FF.
        if let v = key.unicodeScalars.first?.value, (0xF700...0xF8FF).contains(v) {
            key = functionKeys[Int(v)] ?? ""
        }
        if key.isEmpty, let glyph, let g = glyphs[glyph] { key = g }
        if key == " " { key = "␣" }
        guard !key.isEmpty, key.unicodeScalars.first.map({ $0.value >= 0x20 }) ?? false else { return "" }

        // AX modifier bits: 1 = shift, 2 = option, 4 = control, 8 = NO command, 16 = fn
        var s = ""
        if modifiers & 16 != 0 { s += "fn " }
        if modifiers & 4 != 0 { s += "⌃" }
        if modifiers & 2 != 0 { s += "⌥" }
        if modifiers & 1 != 0 { s += "⇧" }
        if modifiers & 8 == 0 { s += "⌘" }
        return s + key.uppercased()
    }
}
