import Foundation
import Observation

/// The object graph, assembled once and injected into the SwiftUI environment.
///
/// Views resolve collaborators from here with `@Environment(AppEnvironment.self)`
/// instead of constructing services themselves, which keeps view code free of
/// dependency-creation logic and makes previews cheap.
@MainActor
@Observable
final class AppEnvironment {
    let appState: DictoraAppState
    let dictation: DictationManager
    let textProcessing: TextProcessingService

    init(container: DependencyContainer) {
        let appState = DictoraAppState(store: container.preferencesStore)
        let textProcessing = TextProcessingService(primary: container.textProcessor)

        self.appState = appState
        self.textProcessing = textProcessing
        self.dictation = DictationManager(
            audioCapture: container.audioCapture,
            recognizer: container.speechRecognizer,
            textProcessing: textProcessing,
            permissions: container.permissions,
            preferencesProvider: { appState.preferences }
        )
    }

    static func live() -> AppEnvironment {
        AppEnvironment(container: .live())
    }

    static func preview(preferences: UserPreferences = UserPreferences(hasCompletedOnboarding: true)) -> AppEnvironment {
        AppEnvironment(container: .preview(preferences: preferences))
    }

    /// Work that must happen once at launch but shouldn't block the first frame.
    func bootstrap() async {
        dictation.refreshPermissionStatuses()
        await textProcessing.refreshAvailability()
    }
}
