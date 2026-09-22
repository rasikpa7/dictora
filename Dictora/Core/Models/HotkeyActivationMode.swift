import Foundation

/// How pressing Dictora's global shortcut starts and stops dictation.
///
/// Lives in `Core` rather than `Platform/macOS` so it can be part of the shared
/// `UserPreferences` value; only the macOS target acts on it.
enum HotkeyActivationMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Press once to start, press again to stop.
    case toggle
    /// Record for as long as the shortcut is held down.
    case holdToTalk

    var id: String { rawValue }

    static let `default`: HotkeyActivationMode = .toggle

    var displayName: String {
        switch self {
        case .toggle: "Press to start and stop"
        case .holdToTalk: "Hold to talk"
        }
    }

    var shortDescription: String {
        switch self {
        case .toggle: "Tap the shortcut once to begin, then tap it again when you're done."
        case .holdToTalk: "Hold the shortcut while you speak. Dictora transcribes when you let go."
        }
    }
}
