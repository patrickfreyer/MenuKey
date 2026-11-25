import Carbon.HIToolbox
import Foundation

struct HotKeyPreset {
    let label: String
    let keyCode: UInt32
    let modifiers: UInt32
    let note: String?
}

enum HotKeyPresets {
    static let all: [HotKeyPreset] = [
        HotKeyPreset(label: "⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), note: nil),
        HotKeyPreset(label: "⌃⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), note: nil),
        HotKeyPreset(label: "⇧⌘ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey), note: nil),
        HotKeyPreset(label: "⇧⌘ /", keyCode: UInt32(kVK_ANSI_Slash), modifiers: UInt32(cmdKey | shiftKey), note: "replaces the Help menu search"),
        HotKeyPreset(label: "⌥⌘ M", keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | optionKey), note: nil),
    ]
}

/// Global hotkey via Carbon — needs no extra permission.
final class HotKey {
    static var onPress: (() -> Void)?
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?

    @discardableResult
    func register(_ preset: HotKeyPreset) -> Bool {
        unregister()
        if !Self.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.onPress?() }
                return noErr
            }, 1, &spec, nil, nil)
            Self.handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x4D4E_4B59), id: 1) // 'MNKY'
        let status = RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
