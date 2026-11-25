import Foundation
import FoundationModels

@Generable
struct MenuGuess {
    @Guide(description: "Up to 6 likely macOS menu command titles, most likely first, worded the way they normally appear in menus, e.g. \"Zoom In\", \"Show Sidebar\", \"Export as PDF…\"")
    var commands: [String]
}

/// Plain-English fallback using Apple's on-device model. Only runs when the
/// normal search finds nothing convincing, so it costs nothing day to day.
enum Assistant {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableReason: String {
        switch SystemLanguageModel.default.availability {
        case .available: return ""
        case .unavailable(.appleIntelligenceNotEnabled): return "turn on Apple Intelligence"
        case .unavailable(.deviceNotEligible): return "not supported on this Mac"
        case .unavailable(.modelNotReady): return "model still downloading"
        default: return "unavailable"
        }
    }

    static func guessCommands(for request: String, app: String, menus: [String]) async -> [String] {
        guard isAvailable else { return [] }
        let session = LanguageModelSession(instructions: """
            You help people find commands in the menu bar of macOS apps. Given what the user wants \
            to do, reply with the menu item titles that most likely do it in this app. Use standard \
            macOS menu wording. Each answer must be a complete menu item title such as "Zoom In" \
            or "Show View Options", never just the name of a top-level menu like "View" or "File". \
            Never explain.
            """)
        let prompt = """
            App: \(app)
            Its menus: \(menus.joined(separator: ", "))
            The user wants to: \(request)
            """
        do {
            let response = try await session.respond(to: prompt, generating: MenuGuess.self,
                                                      options: GenerationOptions(temperature: 0.2))
            return response.content.commands
        } catch {
            return []
        }
    }
}
