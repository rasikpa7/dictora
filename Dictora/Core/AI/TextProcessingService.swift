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
    /// Claude, tried first when the user has connected a key and switched it on.
    private let cloud: (any TextProcessorProtocol)?
    private let cloudTimeout: Duration
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "TextProcessing")

    /// Availability of the *preferred* processor. `.unavailable` is not an error
    /// state — it means results will come from the fallback instead.
    private(set) var primaryAvailability: TextProcessorAvailability = .unavailable("Not checked yet.")

    /// How long the preferred processor gets before the deterministic cleanup
    /// takes over. A stalled model must never keep the user's words hostage.
    private let primaryTimeout: Duration
    /// Why the last attempt to use Claude fell back, or `nil` if it worked (or
    /// wasn't tried). Shown in Settings so a bad key is never a silent mystery.
    private(set) var lastCloudIssue: String?
    private var lastAvailabilityCheck: ContinuousClock.Instant?
    private static let availabilityFreshness = Duration.seconds(60)

    init(
        primary: any TextProcessorProtocol,
        fallback: any TextProcessorProtocol = LocalFallbackTextProcessor(),
        primaryTimeout: Duration = .seconds(6),
        cloud: (any TextProcessorProtocol)? = nil,
        cloudTimeout: Duration = .seconds(10)
    ) {
        self.primary = primary
        self.fallback = fallback
        self.cloud = cloud
        self.cloudTimeout = cloudTimeout
        self.primaryTimeout = primaryTimeout
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
        lastAvailabilityCheck = .now
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

        if let cloud, request.useCloud, await cloud.availability().isAvailable {
            do {
                let text = try await Self.race(timeout: cloudTimeout) {
                    try await cloud.process(request)
                }
                lastCloudIssue = nil
                return ProcessedText(text: text, processor: cloud.kind)
            } catch {
                // Any Claude problem (bad key, offline, slow) falls back to the
                // on-device path, so dictation still finishes.
                lastCloudIssue = error.localizedDescription
                logger.warning(
                    "Claude failed, using on-device rewriting: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        // A positive answer stays valid for a minute; asking the system model on
        // every dictation only adds latency.
        if !primaryAvailability.isAvailable
            || lastAvailabilityCheck.map({ .now - $0 > Self.availabilityFreshness }) ?? true {
            await refreshAvailability()
        }

        if primaryAvailability.isAvailable {
            do {
                let primary = self.primary
                let text = try await Self.race(timeout: primaryTimeout) {
                    try await primary.process(request)
                }
                return ProcessedText(text: text, processor: primary.kind)
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

    /// Runs `work`, but gives up after `timeout`.
    ///
    /// A task group would wait for the slow child to finish, which is exactly
    /// what must not happen, so the two contenders are unstructured and the
    /// first to finish wins; the loser is cancelled and its result ignored.
    private static func race(
        timeout: Duration,
        _ work: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        let gate = RaceGate()
        return try await withCheckedThrowingContinuation { continuation in
            let worker = Task {
                do {
                    let value = try await work()
                    if gate.claim() { continuation.resume(returning: value) }
                } catch {
                    if gate.claim() { continuation.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(for: timeout)
                if gate.claim() {
                    worker.cancel()
                    continuation.resume(throwing: TextProcessingError.generationFailed(
                        "The rewrite took longer than \(timeout.components.seconds) seconds."
                    ))
                }
            }
        }
    }
}

/// One-shot latch: exactly one caller of ``claim()`` ever gets `true`.
private final class RaceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
