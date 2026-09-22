import Foundation
import Observation

/// App-wide UI state and the single mutable copy of the user's preferences.
///
/// Views mutate `preferences` directly; persistence happens here rather than at
/// every call site, so there is exactly one place that writes to storage.
@MainActor
@Observable
final class DictoraAppState {
    var preferences: UserPreferences {
        didSet {
            guard preferences != oldValue else { return }
            store.save(preferences)
        }
    }

    /// Drives the macOS settings window and the iOS settings sheet.
    var isPresentingSettings = false

    private let store: any PreferencesStoring

    init(store: any PreferencesStoring) {
        self.store = store
        self.preferences = store.load()
    }

    var hasCompletedOnboarding: Bool { preferences.hasCompletedOnboarding }

    var currentWritingStyle: WritingStyle { preferences.selectedWritingStyle }

    func completeOnboarding() {
        preferences.hasCompletedOnboarding = true
    }

    /// Exposed for development and for a future "reset Dictora" settings action.
    func resetOnboarding() {
        preferences.hasCompletedOnboarding = false
    }

    func selectWritingStyle(_ style: WritingStyle) {
        preferences.selectedWritingStyle = style
    }
}
