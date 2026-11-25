import Foundation

/// The global shortcuts Dictora offers for dictating from anywhere.
///
/// A fixed list rather than a free-form recorder: every option here is known not
/// to collide with a common system shortcut, and each one can be described
/// honestly in the UI (including what it costs, such as needing Accessibility).
///
/// Lives in `Core` so it can be part of the shared `UserPreferences` value. The
/// mapping to actual key codes is a macOS-only extension in `GlobalHotkeyManager`.
enum ShortcutPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    /// The Fn / Globe key on its own.
    case fnGlobe
    case optionSpace
    case controlOptionSpace
    case commandShiftD
    case controlShiftD

    var id: String { rawValue }

    /// Fn feels best, but it is the only option that cannot work without
    /// Accessibility, so it is not what an unconfigured Mac falls back to.
    static let `default`: ShortcutPreset = .fnGlobe

    /// Used whenever the chosen shortcut cannot be registered.
    static let fallback: ShortcutPreset = .optionSpace

    /// How the shortcut is written on a keyboard, e.g. "⌥Space".
    var displayString: String {
        switch self {
        case .fnGlobe: "Fn"
        case .optionSpace: "⌥Space"
        case .controlOptionSpace: "⌃⌥Space"
        case .commandShiftD: "⇧⌘D"
        case .controlShiftD: "⌃⇧D"
        }
    }

    var displayName: String {
        switch self {
        case .fnGlobe: "Fn / Globe key"
        case .optionSpace: "Option + Space"
        case .controlOptionSpace: "Control + Option + Space"
        case .commandShiftD: "Shift + Command + D"
        case .controlShiftD: "Control + Shift + D"
        }
    }

    /// Only Fn needs it: a lone modifier can't be registered as a system hotkey,
    /// so it has to be observed through an event tap, which requires trust.
    var requiresAccessibility: Bool { self == .fnGlobe }

    var detail: String {
        switch self {
        case .fnGlobe:
            "One key, nothing to reach for. Needs Accessibility access, and the Globe key should be set to “Do Nothing” in Keyboard settings."
        case .optionSpace:
            "Works without Accessibility access. Conflicts with Spotlight only if you've remapped it."
        case .controlOptionSpace:
            "Works without Accessibility access. The safest option if something else already uses ⌥Space."
        case .commandShiftD:
            "Works without Accessibility access. Some apps use this for their own “duplicate” command."
        case .controlShiftD:
            "Works without Accessibility access. Rarely claimed by other apps."
        }
    }
}
