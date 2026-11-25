import Foundation

/// How pressing Dictora's global shortcut starts and stops dictation.
///
/// Lives in `Core` rather than `Platform/macOS` so it can be part of the shared
/// `UserPreferences` value; only the macOS target acts on it.
enum HotkeyActivationMode: String, CaseIterable, Sendable, Identifiable {
    /// Double-press the shortcut to start; a single press stops while listening.
    case doubleTap
    /// Record for as long as the shortcut is held down.
    case holdToTalk

    var id: String { rawValue }

    /// Hold-to-talk matches the one-key dictation feel of Fn-based apps.
    static let `default`: HotkeyActivationMode = .holdToTalk

    var displayName: String {
        switch self {
        case .doubleTap: "Double-tap to start, tap to stop"
        case .holdToTalk: "Hold to talk"
        }
    }

    var shortDescription: String {
        switch self {
        case .doubleTap: "Tap the shortcut twice quickly to begin. Tap once while listening to stop."
        case .holdToTalk: "Hold the shortcut while you speak. Dictora transcribes when you let go."
        }
    }
}

extension HotkeyActivationMode: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case Self.doubleTap.rawValue, "toggle":
            // "toggle" was the pre-Fn raw value; map it so existing preferences
            // keep working after the rename.
            self = .doubleTap
        case Self.holdToTalk.rawValue:
            self = .holdToTalk
        default:
            self = .default
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
