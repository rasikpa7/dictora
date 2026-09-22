#if canImport(FoundationModels)
import Foundation
import FoundationModels
import OSLog

/// On-device rewriting via Apple's system language model.
///
/// A fresh `LanguageModelSession` is created per request: each dictation is
/// independent, and carrying a transcript forward would let one rewrite leak
/// into the next.
@available(macOS 26.0, iOS 26.0, *)
struct FoundationModelTextProcessor: TextProcessorProtocol {
    let kind: TextProcessorKind = .foundationModel

    private let promptBuilder: PromptBuilder
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "FoundationModelTextProcessor")

    init(promptBuilder: PromptBuilder = PromptBuilder()) {
        self.promptBuilder = promptBuilder
    }

    func availability() async -> TextProcessorAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(Self.explanation(for: reason))
        @unknown default:
            return .unavailable("On-device rewriting isn't available on this device.")
        }
    }

    func process(_ request: TextProcessingRequest) async throws -> String {
        let transcript = request.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw TextProcessingError.emptyTranscript }

        if case .unavailable(let reason) = await availability() {
            throw TextProcessingError.processorUnavailable(reason)
        }

        // Rewriting text the user dictated is a content transformation, not
        // open-ended generation; the permissive guardrails exist for exactly
        // this and stop ordinary speech from being refused.
        let model = SystemLanguageModel(
            useCase: .general,
            guardrails: .permissiveContentTransformations
        )
        let session = LanguageModelSession(
            model: model,
            instructions: promptBuilder.instructions(for: request)
        )

        do {
            let response = try await session.respond(
                to: promptBuilder.prompt(for: request),
                options: GenerationOptions(temperature: Self.temperature(for: request.strength))
            )
            let cleaned = promptBuilder.sanitize(response.content)
            // An empty or refused generation must never destroy the user's words.
            return cleaned.isEmpty ? transcript : cleaned
        } catch {
            logger.error("Generation failed: \(error.localizedDescription, privacy: .public)")
            throw TextProcessingError.generationFailed(error.localizedDescription)
        }
    }

    private static func temperature(for strength: TransformationStrength) -> Double {
        switch strength {
        case .minimal: 0.0
        case .balanced: 0.3
        case .rewrite: 0.6
        }
    }

    private static func explanation(
        for reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            "This device doesn't support Apple Intelligence, so Dictora will use basic cleanup instead."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in System Settings to let Dictora rewrite your dictation."
        case .modelNotReady:
            "Apple Intelligence is still preparing. Dictora will use basic cleanup until it's ready."
        @unknown default:
            "On-device rewriting isn't available right now, so Dictora will use basic cleanup."
        }
    }
}
#endif
