import AVFoundation
import Foundation
import Testing

@testable import DictoraMac

// MARK: - Fakes

actor FakeAudio: AudioCapturing {
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var startDelay: Duration = .zero

    func setStartDelay(_ delay: Duration) { startDelay = delay }

    func start(convertingTo outputFormat: AVAudioFormat?) async throws -> AsyncStream<AudioChunk> {
        startCount += 1
        try? await Task.sleep(for: startDelay)
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        self.continuation = continuation
        return stream
    }

    func stop() async {
        stopCount += 1
        continuation?.finish()
        continuation = nil
    }

    /// Simulates the microphone vanishing: the stream ends without `stop()`.
    func endStreamUnexpectedly() {
        continuation?.finish()
        continuation = nil
    }

    var isCapturing: Bool { continuation != nil }
}

actor FakeRecognizer: SpeechRecognizing {
    var text: String
    var finishError: (any Error)?
    var startDelay: Duration = .zero
    private var updates: AsyncThrowingStream<TranscriptionUpdate, any Error>.Continuation?

    init(text: String = "hello world") { self.text = text }

    func setFinishError(_ error: (any Error)?) { finishError = error }
    func setStartDelay(_ delay: Duration) { startDelay = delay }

    func prepare(locale: Locale) async throws -> AVAudioFormat? { nil }

    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, any Error> {
        try? await Task.sleep(for: startDelay)
        let (stream, continuation) = AsyncThrowingStream<TranscriptionUpdate, any Error>.makeStream()
        updates = continuation
        continuation.yield(TranscriptionUpdate(finalizedText: "", volatileText: text))
        return stream
    }

    func append(_ chunk: AudioChunk) async {}

    func finish() async throws {
        updates?.yield(TranscriptionUpdate(finalizedText: text))
        updates?.finish()
        updates = nil
        if let finishError { throw finishError }
    }

    func cancel() async {
        updates?.finish()
        updates = nil
    }
}

struct FakePermissions: DictationPermissionsProviding {
    var microphone: PermissionStatus = .granted
    func microphoneStatus() -> PermissionStatus { microphone }
    func speechStatus() -> PermissionStatus { .granted }
    func requestMicrophone() async -> PermissionStatus { microphone }
    func requestSpeech() async -> PermissionStatus { .granted }
}

struct StubProcessor: TextProcessorProtocol {
    var kind: TextProcessorKind = .foundationModel
    var behaviour: Behaviour = .succeed

    enum Behaviour: Sendable { case succeed, fail, hang }

    func availability() async -> TextProcessorAvailability { .available }

    func process(_ request: TextProcessingRequest) async throws -> String {
        switch behaviour {
        case .succeed: return "Polished: \(request.transcript)"
        case .fail: throw TextProcessingError.generationFailed("boom")
        case .hang:
            try await Task.sleep(for: .seconds(30))
            return "never"
        }
    }
}

@MainActor
func makeManager(
    audio: FakeAudio = FakeAudio(),
    recognizer: FakeRecognizer = FakeRecognizer(),
    permissions: FakePermissions = FakePermissions(),
    processor: StubProcessor = StubProcessor(),
    processorTimeout: Duration = .seconds(6)
) -> DictationManager {
    DictationManager(
        audioCapture: audio,
        recognizer: recognizer,
        textProcessing: TextProcessingService(primary: processor, primaryTimeout: processorTimeout),
        permissions: permissions,
        preferencesProvider: { UserPreferences(hasCompletedOnboarding: true, playSounds: false) }
    )
}

// MARK: - Tests

@Suite("Dictation state machine")
@MainActor
struct DictationManagerTests {
    @Test("A normal session ends with polished text and a history entry")
    func normalSession() async {
        let manager = makeManager()
        await manager.start()
        #expect(manager.state == .listening)

        await manager.stop()
        #expect(manager.state == .completed)
        #expect(manager.result?.polishedText == "Polished: hello world")
        #expect(manager.result?.warning == nil)
        #expect(manager.history.count == 1)
    }

    @Test("A denied microphone fails clearly and opens nothing")
    func microphoneDenied() async {
        let audio = FakeAudio()
        let manager = makeManager(audio: audio, permissions: FakePermissions(microphone: .denied))
        await manager.start()

        #expect(manager.state == .failed(.microphonePermissionDenied))
        #expect(await audio.startCount == 0)
    }

    @Test("A second start while one is running is refused")
    func doubleStart() async {
        let audio = FakeAudio()
        let manager = makeManager(audio: audio)
        await manager.start()
        await manager.start()

        #expect(await audio.startCount == 1)
        #expect(manager.state == .listening)
    }

    @Test("If the rewrite fails, the user still gets exactly what they said")
    func rewriteFailureDeliversRawText() async {
        let manager = makeManager(processor: StubProcessor(kind: .foundationModel, behaviour: .fail))
        await manager.start()
        await manager.stop()

        // The primary processor failing falls back to local cleanup.
        #expect(manager.state == .completed)
        #expect(manager.result?.polishedText.lowercased().contains("hello world") == true)
    }

    @Test("A stalled rewrite times out instead of hanging forever")
    func rewriteTimeout() async {
        let manager = makeManager(
            processor: StubProcessor(kind: .foundationModel, behaviour: .hang),
            processorTimeout: .milliseconds(150)
        )
        await manager.start()

        let began = ContinuousClock.now
        await manager.stop()
        let elapsed = ContinuousClock.now - began

        #expect(manager.state == .completed)
        #expect(manager.result?.processor == .localFallback)
        #expect(elapsed < .seconds(3))
    }

    @Test("A recogniser error after speech still delivers what was heard")
    func recogniserErrorKeepsWords() async {
        let recognizer = FakeRecognizer(text: "keep these words")
        await recognizer.setFinishError(SpeechRecognitionError.failed("analyzer crashed"))
        let manager = makeManager(recognizer: recognizer)
        await manager.start()
        await manager.stop()

        #expect(manager.state == .completed)
        #expect(manager.result?.rawTranscript == "keep these words")
        #expect(manager.result?.warning != nil)
    }

    @Test("Cancelling while the model is still loading leaves nothing running")
    func cancelDuringStart() async {
        let audio = FakeAudio()
        let recognizer = FakeRecognizer()
        await recognizer.setStartDelay(.milliseconds(300))
        let manager = makeManager(audio: audio, recognizer: recognizer)

        let starting = Task { await manager.start() }
        try? await Task.sleep(for: .milliseconds(100))
        await manager.cancel()
        await starting.value

        #expect(manager.state == .idle)
        #expect(await audio.isCapturing == false)
    }

    @Test("The microphone vanishing mid-session is reported")
    func microphoneInterrupted() async {
        let audio = FakeAudio()
        let manager = makeManager(audio: audio)
        var interrupted = false
        manager.onCaptureInterrupted = { interrupted = true }

        await manager.start()
        await audio.endStreamUnexpectedly()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(interrupted)
    }

    @Test("A failed session cannot tear down the next one")
    func failureThenImmediateRestart() async {
        let recognizer = FakeRecognizer(text: "")
        let manager = makeManager(recognizer: recognizer)

        await manager.start()
        await manager.stop()
        #expect(manager.state.error != nil)  // nothing heard

        await recognizer.setText("second try")
        await manager.start()
        #expect(manager.state == .listening)
        await manager.stop()
        #expect(manager.state == .completed)
        #expect(manager.result?.rawTranscript == "second try")
    }

    @Test("History keeps only the most recent results, newest first")
    func historyIsBounded() async {
        let manager = makeManager()
        for _ in 0..<(DictationManager.historyLimit + 3) {
            await manager.start()
            await manager.stop()
        }
        #expect(manager.history.count == DictationManager.historyLimit)
        #expect(manager.history.first?.createdAt ?? .distantPast >= manager.history.last?.createdAt ?? .distantFuture)
    }
}

private extension FakeRecognizer {
    func setText(_ newText: String) { text = newText }
}
