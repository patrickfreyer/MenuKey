import AppKit
import ApplicationServices

enum ItemKind: Int {
    case menu, window, menuExtra, folder, file
}

enum ItemAction {
    case press(AXUIElement)
    case window(app: AXUIElement, window: AXUIElement)
    case folder(URL)
    case file(URL)
    case grantFolderAccess
}

/// One row in the results list: a menu command, a window, a menu bar icon, a folder or a file.
struct SearchItem: Identifiable {
    let id: String
    let kind: ItemKind
    let title: String
    let subtitle: String
    var shortcut: String = ""
    var checked = false
    var icon: NSImage?
    var suggested = false           // came from the plain-English fallback
    var windowID: CGWindowID?       // for previews
    let action: ItemAction
    let frecencyKey: String
    let order: Int                  // natural order within its source

    let titleKey: [Character]
    let subtitleKey: [Character]

    init(id: String, kind: ItemKind, title: String, subtitle: String, shortcut: String = "", checked: Bool = false,
         icon: NSImage? = nil, windowID: CGWindowID? = nil, action: ItemAction, frecencyKey: String, order: Int) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.shortcut = shortcut
        self.checked = checked
        self.icon = icon
        self.windowID = windowID
        self.action = action
        self.frecencyKey = frecencyKey
        self.order = order
        self.titleKey = Array(Self.normalize(title))
        self.subtitleKey = Array(Self.normalize(subtitle))
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

/// Shared Accessibility helpers.
enum AX {
    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func string(_ element: AXUIElement, _ name: String) -> String {
        ((attribute(element, name) as String?) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) ?? []
    }
}

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError
