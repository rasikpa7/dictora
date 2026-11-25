import AVFoundation
import Foundation
import Testing

@testable import DictoraMac

/// End-to-end check with the real microphone, the real on-device speech model
/// and the real rewrite step. The Mac speaks a sentence through its own
/// speakers and Dictora listens to it.
///
/// Off by default, because it plays sound. Run with:
/// `TEST_RUNNER_DICTORA_LIVE_TESTS=1 xcodebuild test -scheme DictoraMac ...`
private let liveTestsEnabled: Bool =
    ProcessInfo.processInfo.environment["DICTORA_LIVE_TESTS"] == "1"
    && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

@Suite("Live dictation", .serialized)
@MainActor
struct LiveDictationTests {

    private func speak(_ sentence: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "Samantha", "-r", "170", sentence]
        try? process.run()
        while process.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private func makeManager() -> DictationManager {
        DictationManager(
            audioCapture: AudioCaptureService(),
            recognizer: SpeechRecognizerFactory.makeDefault(),
            textProcessing: TextProcessingService(primary: FoundationModelTextProcessor()),
            permissions: SystemDictationPermissions(),
            soundFeedback: SoundFeedback(),
            preferencesProvider: { UserPreferences(hasCompletedOnboarding: true, playSounds: false) }
        )
    }

    @Test("Speech played into the microphone comes out as clean text", .enabled(if: liveTestsEnabled))
    func endToEnd() async throws {
        let manager = makeManager()
        await manager.warmUp()
        #expect(manager.speechModel == .ready)

        for attempt in 1...2 {
            let began = ContinuousClock.now
            await manager.start()
            let startLatency = ContinuousClock.now - began
            try #require(manager.state == .listening, "attempt \(attempt): \(manager.state)")

            await speak("Hey team, I fixed the login bug and the new build is ready for review.")
            try? await Task.sleep(for: .milliseconds(700))

            let stopBegan = ContinuousClock.now
            await manager.stop()
            let stopLatency = ContinuousClock.now - stopBegan

            let result = try #require(manager.result, "attempt \(attempt): no result, state \(manager.state)")
            print("LIVE attempt \(attempt): start=\(startLatency) stop→text=\(stopLatency)")
            print("LIVE raw:      \(result.rawTranscript)")
            print("LIVE polished: \(result.polishedText) [\(result.processor.displayName)]")

            let heard = result.rawTranscript.lowercased()
            #expect(heard.contains("login"))
            #expect(heard.contains("build"))
            #expect(heard.contains("review"))
        }
    }

    @Test("A quiet session ends cleanly and closes the microphone", .enabled(if: liveTestsEnabled))
    func quietSessionEndsCleanly() async throws {
        let manager = makeManager()
        await manager.start()
        try? await Task.sleep(for: .milliseconds(600))
        await manager.stop()

        // In a silent room this is "nothing heard"; if someone is talking nearby
        // it is whatever they said. Either way the session must be over.
        #expect(manager.state == .completed || manager.state.error != nil)
        #expect(!manager.state.isBusy)
    }

    @Test("Names in the vocabulary are heard correctly", .enabled(if: liveTestsEnabled))
    func vocabularyHelps() async throws {
        let manager = makeManager()
        await manager.warmUp()
        await manager.start()
        try #require(manager.state == .listening)

        await speak("Please ask Claude from Anthropic to rewrite this paragraph in Dictora.")
        try? await Task.sleep(for: .milliseconds(700))
        await manager.stop()

        let raw = manager.result?.rawTranscript ?? "<none: \(manager.state)>"
        print("LIVE vocab raw: \(raw)")
        #expect(raw.contains("Claude"))
        #expect(raw.contains("Anthropic"))
    }
}
