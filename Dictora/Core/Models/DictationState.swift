import Foundation

/// The dictation pipeline as a finite state machine.
///
/// `DictationManager` owns the only mutable instance; views read it and never
/// write to it. The completed result and last error are exposed separately by
/// the manager so this enum stays cheap to compare.
enum DictationState: Equatable, Sendable {
    case idle
    case requestingPermission
    case listening
    case transcribing
    case processing
    case completed
    case failed(DictationError)

    /// True while the microphone is open.
    var isCapturing: Bool { self == .listening }

    /// True while Dictora is working and the user should wait.
    var isBusy: Bool {
        switch self {
        case .requestingPermission, .listening, .transcribing, .processing: true
        case .idle, .completed, .failed: false
        }
    }

    /// True when starting a new dictation is a sensible action.
    var canStart: Bool {
        switch self {
        case .idle, .completed, .failed: true
        case .requestingPermission, .listening, .transcribing, .processing: false
        }
    }

    var error: DictationError? {
        if case .failed(let error) = self { return error }
        return nil
    }

    /// Short status text suitable for the floating overlay and menu bar.
    var statusText: String {
        switch self {
        case .idle: "Ready"
        case .requestingPermission: "Checking permissions…"
        case .listening: "Listening…"
        case .transcribing: "Transcribing…"
        case .processing: "Processing…"
        case .completed: "Done"
        case .failed: "Failed"
        }
    }
}
