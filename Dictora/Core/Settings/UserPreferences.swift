import Foundation

/// Everything the user can configure, as one value type.
///
/// Keeping preferences in a single `Codable` struct means the persistence layer
/// has exactly one thing to read and write, and tests can build a preferences
/// value without touching `UserDefaults`.
struct UserPreferences: Codable, Equatable, Sendable {
    var hasCompletedOnboarding: Bool
    var selectedWritingStyle: WritingStyle
    /// Used when ``selectedWritingStyle`` is `.custom`.
    var customInstructions: String
    /// Layered on top of any style, preset or custom.
    var additionalInstructions: String
    var transformationStrength: TransformationStrength
    var playSounds: Bool
    var showFloatingIndicator: Bool
    /// macOS only. Not wired to `SMAppService` yet — see `MacPlatformServices`.
    var launchAtLogin: Bool

    init(
        hasCompletedOnboarding: Bool = false,
        selectedWritingStyle: WritingStyle = .default,
        customInstructions: String = "",
        additionalInstructions: String = "",
        transformationStrength: TransformationStrength = .default,
        playSounds: Bool = true,
        showFloatingIndicator: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.selectedWritingStyle = selectedWritingStyle
        self.customInstructions = customInstructions
        self.additionalInstructions = additionalInstructions
        self.transformationStrength = transformationStrength
        self.playSounds = playSounds
        self.showFloatingIndicator = showFloatingIndicator
        self.launchAtLogin = launchAtLogin
    }

    /// Decoding tolerates preferences written by an older build that lacked a key.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UserPreferences()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decode(T.self, forKey: key)) ?? fallback
        }
        hasCompletedOnboarding = value(.hasCompletedOnboarding, defaults.hasCompletedOnboarding)
        selectedWritingStyle = value(.selectedWritingStyle, defaults.selectedWritingStyle)
        customInstructions = value(.customInstructions, defaults.customInstructions)
        additionalInstructions = value(.additionalInstructions, defaults.additionalInstructions)
        transformationStrength = value(.transformationStrength, defaults.transformationStrength)
        playSounds = value(.playSounds, defaults.playSounds)
        showFloatingIndicator = value(.showFloatingIndicator, defaults.showFloatingIndicator)
        launchAtLogin = value(.launchAtLogin, defaults.launchAtLogin)
    }

    /// The style instruction with the user's own custom text already resolved.
    var resolvedStyleInstruction: String {
        selectedWritingStyle.instruction(customInstructions: customInstructions)
    }

    /// False when the user picked `.custom` but never wrote any instructions.
    var isWritingConfigurationValid: Bool {
        guard selectedWritingStyle.requiresCustomInstructions else { return true }
        return !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
