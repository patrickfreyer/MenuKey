import Foundation

/// JumpKey was called MenuKey up to v1.1. On first launch, carry over its
/// settings and usage history so nothing has to be set up again.
enum Migration {
    private static let oldDomain = "com.patrickfreyer.MenuKey"
    private static let doneKey = "migratedFromMenuKey"

    static func fromMenuKeyIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        if let old = defaults.persistentDomain(forName: oldDomain) {
            // Launch-at-login was registered for the old app, so JumpKey must register itself again.
            for (key, value) in old where key != "didSetUpLaunchAtLogin" && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldDir = support.appendingPathComponent("MenuKey", isDirectory: true)
        let newDir = support.appendingPathComponent("JumpKey", isDirectory: true)
        if FileManager.default.fileExists(atPath: oldDir.path), !FileManager.default.fileExists(atPath: newDir.path) {
            try? FileManager.default.moveItem(at: oldDir, to: newDir)
        }
    }
}
