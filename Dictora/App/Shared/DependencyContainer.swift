import Foundation

/// Builds the concrete services the app runs on.
///
/// All "which implementation does this OS support?" decisions live here, so the
/// rest of the codebase only ever sees protocols and tests can substitute fakes
/// by constructing a container directly.
@MainActor
struct DependencyContainer {
    let preferencesStore: any PreferencesStoring
    let permissions: any DictationPermissionsProviding
    let audioCapture: any AudioCapturing
    let speechRecognizer: any SpeechRecognizing
    let textProcessor: any TextProcessorProtocol

    init(
        preferencesStore: any PreferencesStoring,
        permissions: any DictationPermissionsProviding,
        audioCapture: any AudioCapturing,
        speechRecognizer: any SpeechRecognizing,
        textProcessor: any TextProcessorProtocol
    ) {
        self.preferencesStore = preferencesStore
        self.permissions = permissions
        self.audioCapture = audioCapture
        self.speechRecognizer = speechRecognizer
        self.textProcessor = textProcessor
    }

    static func live() -> DependencyContainer {
        DependencyContainer(
            preferencesStore: UserDefaultsPreferencesStore(),
            permissions: SystemDictationPermissions(),
            audioCapture: AudioCaptureService(),
            speechRecognizer: SpeechRecognizerFactory.makeDefault(),
            textProcessor: makeTextProcessor()
        )
    }

    /// In-memory container for SwiftUI previews: no persistence, no microphone.
    static func preview(preferences: UserPreferences = UserPreferences(hasCompletedOnboarding: true)) -> DependencyContainer {
        DependencyContainer(
            preferencesStore: InMemoryPreferencesStore(preferences),
            permissions: SystemDictationPermissions(),
            audioCapture: AudioCaptureService(),
            speechRecognizer: UnsupportedSpeechRecognizer(),
            textProcessor: LocalFallbackTextProcessor()
        )
    }

    /// Apple Intelligence when the SDK and OS provide it, deterministic cleanup otherwise.
    private static func makeTextProcessor() -> any TextProcessorProtocol {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return FoundationModelTextProcessor()
        }
        #endif
        return LocalFallbackTextProcessor()
    }
}
