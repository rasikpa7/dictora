#if os(macOS)
import Foundation
import Testing

@testable import DictoraMac

/// The shortcut flow with fake audio, so timing is exact. These guard the bug
/// where letting go of the key while Dictora was still starting left the
/// microphone open until the next press.
@Suite("Shortcut flow", .serialized)
@MainActor
struct SystemDictationCoordinatorTests {
    private struct Rig {
        let coordinator: SystemDictationCoordinator
        let environment: AppEnvironment
        let audio: FakeAudio
        let recognizer: FakeRecognizer
    }

    private func makeRig(recognizerStartDelay: Duration = .zero) async -> Rig {
        let audio = FakeAudio()
        let recognizer = FakeRecognizer(text: "ship it today")
        await recognizer.setStartDelay(recognizerStartDelay)

        let preferences = UserPreferences(
            hasCompletedOnboarding: true,
            playSounds: false,
            showFloatingIndicator: false,
            globalShortcutEnabled: false,
            hotkeyActivationMode: .holdToTalk,
            insertTextAutomatically: false
        )
        let container = DependencyContainer(
            preferencesStore: InMemoryPreferencesStore(preferences),
            permissions: FakePermissions(),
            audioCapture: audio,
            speechRecognizer: recognizer,
            textProcessor: LocalFallbackTextProcessor()
        )
        let environment = AppEnvironment(container: container)
        let coordinator = SystemDictationCoordinator(environment: environment, platform: MacPlatformServices())
        return Rig(coordinator: coordinator, environment: environment, audio: audio, recognizer: recognizer)
    }

    private func settle(_ milliseconds: Int = 600) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    @Test("A normal hold: press, speak, release delivers the text")
    func normalHold() async {
        let rig = await makeRig()
        rig.coordinator.handleShortcutPress()
        await settle(700)
        #expect(rig.environment.dictation.state == .listening)

        rig.coordinator.handleShortcutRelease()
        await settle()
        #expect(rig.environment.dictation.state == .completed)
        #expect(rig.environment.dictation.result?.rawTranscript == "ship it today")
        #expect(await rig.audio.isCapturing == false)
    }

    @Test("Letting go while still starting ends the session instead of leaving the mic open")
    func releaseDuringStartup() async {
        // Startup takes ~1.2 s; the key is held for 0.8 s, then released mid-startup.
        let rig = await makeRig(recognizerStartDelay: .milliseconds(1200))
        rig.coordinator.handleShortcutPress()
        await settle(800)
        #expect(rig.environment.dictation.state == .requestingPermission)

        rig.coordinator.handleShortcutRelease()
        await settle(2000)

        #expect(rig.environment.dictation.state == .completed)
        #expect(rig.environment.dictation.result?.rawTranscript == "ship it today")
        #expect(await rig.audio.isCapturing == false)
    }

    @Test("An accidental tap ends quietly with no error and no text")
    func accidentalTap() async {
        let rig = await makeRig()
        rig.coordinator.handleShortcutPress()
        await settle(150)
        rig.coordinator.handleShortcutRelease()
        await settle(800)

        #expect(rig.environment.dictation.state == .idle)
        #expect(rig.environment.dictation.result == nil)
        #expect(await rig.audio.isCapturing == false)
    }

    @Test("A new press after a finished session starts a fresh one")
    func pressAfterFinish() async {
        let rig = await makeRig()
        for _ in 0..<2 {
            rig.coordinator.handleShortcutPress()
            await settle(700)
            #expect(rig.environment.dictation.state == .listening)
            rig.coordinator.handleShortcutRelease()
            await settle(600)
            #expect(rig.environment.dictation.state == .completed)
        }
        #expect(rig.environment.dictation.history.count == 2)
    }
}
#endif
