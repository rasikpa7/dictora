import Foundation
import OSLog

/// A rewritten transcript plus the processor that actually produced it.
struct ProcessedText: Equatable, Sendable {
    let text: String
    let processor: TextProcessorKind
}

/// Coordinates the preferred text processor and the offline fallback.
///
/// The rest of the app talks to this service instead of choosing a processor
/// itself, which keeps the "Apple Intelligence, else basic cleanup" decision in
/// one place and gives the UI a single observable availability state.
@MainActor
@Observable
final class TextProcessingService {
    private let primary: any TextProcessorProtocol
    private let fallback: any TextProcessorProtocol
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "TextProcessing")

    /// Availability of the *preferred* processor. `.unavailable` is not an error
    /// state — it means results will come from the fallback instead.
    private(set) var primaryAvailability: TextProcessorAvailability = .unavailable("Not checked yet.")

    init(primary: any TextProcessorProtocol, fallback: any TextProcessorProtocol = LocalFallbackTextProcessor()) {
        self.primary = primary
        self.fallback = fallback
    }

    /// The processor that would run if the user dictated right now.
    var activeProcessorKind: TextProcessorKind {
        primaryAvailability.isAvailable ? primary.kind : fallback.kind
    }

    /// True when the preferred processor is a real model rather than the fallback.
    var supportsIntelligentRewriting: Bool {
        primary.kind == .foundationModel
    }

    @discardableResult
    func refreshAvailability() async -> TextProcessorAvailability {
        let availability = await primary.availability()
        primaryAvailability = availability
        return availability
    }

    func process(_ request: TextProcessingRequest) async throws -> ProcessedText {
        guard !request.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextProcessingError.emptyTranscript
        }
        if request.style.requiresCustomInstructions,
           request.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TextProcessingError.missingCustomInstructions
        }

        await refreshAvailability()

        if primaryAvailability.isAvailable {
            do {
                return ProcessedText(text: try await primary.process(request), processor: primary.kind)
            } catch {
                // A model failure must not cost the user their dictation, so we
                // degrade to deterministic cleanup rather than surfacing an error.
                logger.warning(
                    "Primary processor failed, using fallback: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return ProcessedText(text: try await fallback.process(request), processor: fallback.kind)
    }
}
