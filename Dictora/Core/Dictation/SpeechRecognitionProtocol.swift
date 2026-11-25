import AVFoundation
import Foundation

/// A snapshot of the transcript while dictation is in progress.
///
/// `volatileText` is the recogniser's current best guess for audio it has not
/// committed to yet; it is replaced wholesale on each update, while
/// `finalizedText` only ever grows.
struct TranscriptionUpdate: Equatable, Sendable {
    var finalizedText: String
    var volatileText: String

    init(finalizedText: String = "", volatileText: String = "") {
        self.finalizedText = finalizedText
        self.volatileText = volatileText
    }

    /// What the user should see right now.
    var displayText: String {
        let volatile = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !volatile.isEmpty else { return finalizedText }
        return finalizedText.isEmpty ? volatile : finalizedText + " " + volatile
    }

    var isEmpty: Bool { displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum SpeechRecognitionError: LocalizedError, Equatable, Sendable {
    case unsupportedOnThisSystem
    case localeNotSupported(String)
    case modelAssetsUnavailable(String)
    case notPrepared
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOnThisSystem:
            "This version of the operating system doesn't provide on-device speech recognition for Dictora."
        case .localeNotSupported(let identifier):
            "Speech recognition isn't available for \(identifier)."
        case .modelAssetsUnavailable(let detail):
            detail
        case .notPrepared:
            "Speech recognition wasn't started correctly."
        case .failed(let detail):
            detail
        }
    }
}

/// Transcription boundary.
///
/// The protocol is deliberately push-based — the caller owns audio capture and
/// feeds chunks in — so the same interface fits Apple's `SpeechAnalyzer`, a
/// future streaming backend, or a fake used in tests.
protocol SpeechRecognizing: Sendable {
    /// Downloads the on-device model if needed and loads it into memory, so the
    /// first dictation after launch starts as fast as every later one.
    /// `onProgress` receives 0…1 while a download runs, or `nil` when the
    /// fraction is unknown.
    func warmUp(locale: Locale, onProgress: @escaping @Sendable (Double?) -> Void) async throws

    /// Prepares the recogniser and returns the audio format incoming chunks must
    /// be converted to, or `nil` if any format is acceptable.
    func prepare(locale: Locale) async throws -> AVAudioFormat?

    /// Names and terms the recogniser should favour, such as people and products.
    /// Applied to the next ``start()``.
    func setVocabulary(_ terms: [String]) async

    /// Begins analysis. The stream finishes after ``finish()`` drains the audio.
    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, any Error>

    func append(_ chunk: AudioChunk) async

    /// Stops accepting audio and waits for the last results to be finalized.
    func finish() async throws

    /// Abandons the session without waiting for final results.
    func cancel() async
}

extension SpeechRecognizing {
    func setVocabulary(_ terms: [String]) async {}

    func warmUp(locale: Locale, onProgress: @escaping @Sendable (Double?) -> Void) async throws {}
}

/// Used when the running OS predates Apple's on-device `SpeechAnalyzer` stack.
///
/// It fails with a clear, explainable error instead of crashing, which keeps
/// Dictora launchable if the deployment target is ever lowered.
struct UnsupportedSpeechRecognizer: SpeechRecognizing {
    func prepare(locale: Locale) async throws -> AVAudioFormat? {
        throw SpeechRecognitionError.unsupportedOnThisSystem
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, any Error> {
        throw SpeechRecognitionError.unsupportedOnThisSystem
    }

    func append(_ chunk: AudioChunk) async {}
    func finish() async throws {}
    func cancel() async {}
}
