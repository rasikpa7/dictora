import Foundation

/// How Dictora should rewrite a raw dictation transcript.
///
/// The raw values are persisted in `UserDefaults`, so they must stay stable.
enum WritingStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case grammarOnly
    case professional
    case developer
    case natural
    case custom

    var id: String { rawValue }

    static let `default`: WritingStyle = .professional

    var displayName: String {
        switch self {
        case .grammarOnly: "Grammar Only"
        case .professional: "Professional"
        case .developer: "Developer"
        case .natural: "Natural"
        case .custom: "Custom"
        }
    }

    var shortDescription: String {
        switch self {
        case .grammarOnly:
            "Fix grammar, punctuation, capitalization and obvious speech-recognition mistakes."
        case .professional:
            "Rewrite your dictation to sound clear, concise and professional."
        case .developer:
            "Preserve technical terminology and developer language while improving readability."
        case .natural:
            "Clean up your speech while keeping your natural tone."
        case .custom:
            "Define exactly how your dictation should be transformed."
        }
    }

    var symbolName: String {
        switch self {
        case .grammarOnly: "textformat.abc"
        case .professional: "briefcase"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .natural: "leaf"
        case .custom: "slider.horizontal.3"
        }
    }

    /// Whether the style is meaningless without user-supplied instructions.
    var requiresCustomInstructions: Bool { self == .custom }

    /// The instruction that defines the style itself, before any user additions.
    ///
    /// `.custom` has no built-in instruction; use ``instruction(customInstructions:)``
    /// so the user's own text is substituted in.
    var baseInstruction: String {
        switch self {
        case .grammarOnly:
            """
            Correct grammar, punctuation, capitalization, and obvious \
            speech-recognition errors. Preserve the user's wording and meaning \
            as closely as possible.
            """
        case .professional:
            """
            Rewrite the dictated text so it is clear, concise, natural, and \
            professional. Preserve the user's meaning. Do not introduce new \
            information.
            """
        case .developer:
            """
            Improve readability while preserving technical terminology, API \
            names, variable names, class names, filenames, ticket IDs, \
            commands, acronyms, and code-related language. Never invent \
            technical details.
            """
        case .natural:
            """
            Remove filler words and obvious speech-recognition errors while \
            preserving the user's natural tone and vocabulary.
            """
        case .custom:
            """
            Rewrite the dictated text exactly as the user has instructed below. \
            Preserve the user's meaning and do not introduce new information.
            """
        }
    }

    /// The effective style instruction, resolving `.custom` against the user's own text.
    func instruction(customInstructions: String) -> String {
        let trimmed = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self == .custom, !trimmed.isEmpty else { return baseInstruction }
        return baseInstruction + "\n\nUser's rewriting instructions:\n" + trimmed
    }
}
