import Foundation

/// Everything a processor needs to rewrite one transcript.
///
/// Passing a value type rather than a long parameter list keeps the protocol
/// stable as new knobs (per-app styles, personal dictionary) are added.
struct TextProcessingRequest: Equatable, Sendable {
    var transcript: String
    var style: WritingStyle
    var customInstructions: String
    var additionalInstructions: String
    var strength: TransformationStrength

    init(
        transcript: String,
        style: WritingStyle,
        customInstructions: String = "",
        additionalInstructions: String = "",
        strength: TransformationStrength = .default
    ) {
        self.transcript = transcript
        self.style = style
        self.customInstructions = customInstructions
        self.additionalInstructions = additionalInstructions
        self.strength = strength
    }

    init(transcript: String, preferences: UserPreferences) {
        self.init(
            transcript: transcript,
            style: preferences.selectedWritingStyle,
            customInstructions: preferences.customInstructions,
            additionalInstructions: preferences.additionalInstructions,
            strength: preferences.transformationStrength
        )
    }
}

/// Whether a processor can actually run right now.
///
/// Apple Intelligence can be absent for reasons the app cannot fix (ineligible
/// hardware, feature switched off, model still downloading), so this is a
/// first-class state rather than an error thrown at dictation time.
enum TextProcessorAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }

    var explanation: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

enum TextProcessingError: LocalizedError, Equatable, Sendable {
    case emptyTranscript
    case missingCustomInstructions
    case processorUnavailable(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript: "There was nothing to rewrite."
        case .missingCustomInstructions: "Custom writing style needs your own instructions."
        case .processorUnavailable(let reason): reason
        case .generationFailed(let reason): reason
        }
    }
}

/// The only text-rewriting abstraction the rest of Dictora depends on.
///
/// Nothing outside `Core/AI` imports `FoundationModels`, so the app keeps
/// building and running on hardware where Apple Intelligence is unavailable.
protocol TextProcessorProtocol: Sendable {
    var kind: TextProcessorKind { get }

    /// Checked before each dictation so the UI can explain itself up front.
    func availability() async -> TextProcessorAvailability

    func process(_ request: TextProcessingRequest) async throws -> String
}

extension TextProcessorProtocol {
    /// Convenience matching the conceptual signature used across the codebase.
    func process(
        transcript: String,
        style: WritingStyle,
        customInstructions: String = "",
        additionalInstructions: String = "",
        transformationStrength: TransformationStrength = .default
    ) async throws -> String {
        try await process(
            TextProcessingRequest(
                transcript: transcript,
                style: style,
                customInstructions: customInstructions,
                additionalInstructions: additionalInstructions,
                strength: transformationStrength
            )
        )
    }
}
