import Foundation

/// Every user-visible failure mode of the dictation pipeline.
///
/// Underlying system errors are reduced to a message string so the whole model
/// stays `Equatable` and `Sendable` and can live inside ``DictationState``.
enum DictationError: LocalizedError, Equatable, Sendable {
    case microphonePermissionDenied
    case speechPermissionDenied
    case speechRecognitionUnavailable(String)
    case customInstructionsMissing
    case nothingHeard
    case audioCaptureFailed(String)
    case transcriptionFailed(String)
    case textProcessingFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Dictora can't hear you"
        case .speechPermissionDenied:
            "Speech recognition is turned off"
        case .speechRecognitionUnavailable:
            "Speech recognition isn't available"
        case .customInstructionsMissing:
            "Custom instructions are required"
        case .nothingHeard:
            "Dictora didn't catch anything"
        case .audioCaptureFailed:
            "Microphone capture failed"
        case .transcriptionFailed:
            "Transcription failed"
        case .textProcessingFailed:
            "Rewriting failed"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            "Allow microphone access for Dictora in System Settings › Privacy & Security › Microphone."
        case .speechPermissionDenied:
            "Allow speech recognition for Dictora in System Settings › Privacy & Security › Speech Recognition."
        case .speechRecognitionUnavailable(let detail):
            detail
        case .customInstructionsMissing:
            "Add your own instructions, or pick a different writing style."
        case .nothingHeard:
            "Try again and speak a little closer to the microphone."
        case .audioCaptureFailed(let detail):
            detail
        case .transcriptionFailed(let detail):
            detail
        case .textProcessingFailed(let detail):
            detail
        }
    }
}
