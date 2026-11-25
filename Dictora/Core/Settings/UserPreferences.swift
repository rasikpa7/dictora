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
    /// macOS only. Whether a global shortcut triggers dictation from any app.
    var globalShortcutEnabled: Bool
    /// macOS only. Which global shortcut starts dictation.
    var shortcutPreset: ShortcutPreset
    /// macOS only. Double-tap to start (tap once to stop) versus hold-to-talk.
    var hotkeyActivationMode: HotkeyActivationMode
    /// macOS only. When false, shortcut-triggered results are copied to the
    /// clipboard instead of being typed into the focused field.
    var insertTextAutomatically: Bool
    /// Use Claude for rewriting when an API key is connected. The key itself
    /// lives in the Keychain, never here.
    var useClaude: Bool
    var claudeModel: ClaudeModel
    /// Names and terms to spell exactly, one per line or comma-separated.
    var customVocabulary: String

    init(
        hasCompletedOnboarding: Bool = false,
        selectedWritingStyle: WritingStyle = .default,
        customInstructions: String = "",
        additionalInstructions: String = "",
        transformationStrength: TransformationStrength = .default,
        playSounds: Bool = true,
        showFloatingIndicator: Bool = true,
        launchAtLogin: Bool = false,
        globalShortcutEnabled: Bool = true,
        shortcutPreset: ShortcutPreset = .default,
        hotkeyActivationMode: HotkeyActivationMode = .default,
        insertTextAutomatically: Bool = true,
        useClaude: Bool = true,
        claudeModel: ClaudeModel = .default,
        customVocabulary: String = ""
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.selectedWritingStyle = selectedWritingStyle
        self.customInstructions = customInstructions
        self.additionalInstructions = additionalInstructions
        self.transformationStrength = transformationStrength
        self.playSounds = playSounds
        self.showFloatingIndicator = showFloatingIndicator
        self.launchAtLogin = launchAtLogin
        self.globalShortcutEnabled = globalShortcutEnabled
        self.shortcutPreset = shortcutPreset
        self.hotkeyActivationMode = hotkeyActivationMode
        self.insertTextAutomatically = insertTextAutomatically
        self.useClaude = useClaude
        self.claudeModel = claudeModel
        self.customVocabulary = customVocabulary
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
        globalShortcutEnabled = value(.globalShortcutEnabled, defaults.globalShortcutEnabled)
        shortcutPreset = value(.shortcutPreset, defaults.shortcutPreset)
        hotkeyActivationMode = value(.hotkeyActivationMode, defaults.hotkeyActivationMode)
        insertTextAutomatically = value(.insertTextAutomatically, defaults.insertTextAutomatically)
        useClaude = value(.useClaude, defaults.useClaude)
        claudeModel = value(.claudeModel, defaults.claudeModel)
        customVocabulary = value(.customVocabulary, defaults.customVocabulary)
    }

    /// Words Dictora always knows how to spell, plus the user's own.
    static let builtInVocabulary = ["Claude", "Anthropic", "Dictora"]

    /// The terms handed to the recogniser and the rewriter.
    var vocabularyTerms: [String] {
        let custom = customVocabulary
            .components(separatedBy: CharacterSet(charactersIn: ",\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return (Self.builtInVocabulary + custom).filter { seen.insert($0.lowercased()).inserted }
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
