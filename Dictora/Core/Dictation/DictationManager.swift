import AVFoundation
import Foundation
import OSLog

/// Whether the on-device speech model is ready to use.
enum SpeechModelStatus: Equatable, Sendable {
    case unknown
    case preparing
    /// Downloading; the fraction is `nil` while unknown.
    case downloading(Double?)
    case ready
    case unavailable(String)

    /// A short line for the overlay and menu, or `nil` when there's nothing to say.
    var note: String? {
        switch self {
        case .downloading(let fraction?):
            "Downloading speech model · \(Int((fraction * 100).rounded()))%"
        case .downloading(nil):
            "Downloading speech model…"
        case .preparing:
            "Loading speech model…"
        case .unknown, .ready, .unavailable:
            nil
        }
    }
}

/// Orchestrates the whole dictation pipeline:
/// audio capture → speech recognition → text processing → result.
///
/// It owns the state machine and nothing else: every step is delegated to a
/// service behind a protocol, so this type stays small and the individual
/// stages remain independently testable and replaceable.
///
/// Two promises shape the code below. First, **the user's words are never
/// thrown away**: once speech has been captured, any later failure still
/// delivers the best text available. Second, **a session can always be ended**:
/// a stop request is honoured whatever stage the pipeline is in.
@MainActor
@Observable
final class DictationManager {
    private(set) var state: DictationState = .idle
    private(set) var transcript = TranscriptionUpdate()
    private(set) var result: DictationResult?
    private(set) var microphonePermission: PermissionStatus = .notDetermined
    private(set) var speechPermission: PermissionStatus = .notDetermined
    /// Live mic meter for the floating voice bars (0…1 bands, low→high pitch).
    private(set) var voiceMeter = VoiceMeterReading.silent
    private(set) var speechModel: SpeechModelStatus = .unknown
    /// The most recent finished dictations, newest first. Kept in memory only,
    /// so what the user said is never written to disk.
    private(set) var history: [DictationResult] = []

    /// Called when the microphone stops delivering audio without being asked to
    /// (unplugged, switched, taken over by another app) while listening.
    var onCaptureInterrupted: (@MainActor () -> Void)?

    static let historyLimit = 20

    private let audioCapture: any AudioCapturing
    private let recognizer: any SpeechRecognizing
    private let textProcessing: TextProcessingService
    private let permissions: any DictationPermissionsProviding
    private let soundFeedback: SoundFeedback
    /// Read lazily at dictation time so preference changes always take effect,
    /// without the manager holding a reference to the app's settings object.
    private let preferencesProvider: @MainActor () -> UserPreferences

    private var audioPumpTask: Task<Void, Never>?
    private var transcriptTask: Task<Void, Never>?
    /// Cleanup started by ``fail(with:)``. The next session waits for it, so a
    /// late teardown can never cancel work that belongs to a newer session.
    private var cleanupTask: Task<Void, Never>?
    private var warmUpTask: Task<Void, Never>?
    /// True once at least one microphone buffer reached the recogniser this session.
    private var didReceiveAudio = false
    /// Ignores transcript / audio callbacks that belong to a previous session.
    private var sessionID = UUID()
    private var lastMeterPublish: ContinuousClock.Instant?
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "DictationManager")

    init(
        audioCapture: any AudioCapturing,
        recognizer: any SpeechRecognizing,
        textProcessing: TextProcessingService,
        permissions: any DictationPermissionsProviding,
        soundFeedback: SoundFeedback = SoundFeedback(),
        preferencesProvider: @escaping @MainActor () -> UserPreferences
    ) {
        self.audioCapture = audioCapture
        self.recognizer = recognizer
        self.textProcessing = textProcessing
        self.permissions = permissions
        self.soundFeedback = soundFeedback
        self.preferencesProvider = preferencesProvider
        refreshPermissionStatuses()
    }

    // MARK: - Permissions

    func refreshPermissionStatuses() {
        microphonePermission = permissions.microphoneStatus()
        speechPermission = permissions.speechStatus()
    }

    @discardableResult
    func requestPermissions() async -> Bool {
        let statuses = await permissions.requestAll()
        microphonePermission = statuses.microphone
        speechPermission = statuses.speech
        return statuses.microphone.isGranted && statuses.speech.isGranted
    }

    // MARK: - Warm-up

    /// Downloads the speech model if needed and loads it, so dictation starts
    /// instantly. Safe to call repeatedly; concurrent calls share one run.
    func warmUp() async {
        if case .ready = speechModel { return }
        if let warmUpTask {
            await warmUpTask.value
            return
        }

        speechModel = .preparing
        let task = Task { [weak self, recognizer] in
            do {
                try await recognizer.warmUp(locale: .current) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.speechModel != .ready else { return }
                        self.speechModel = .downloading(fraction)
                    }
                }
                self?.speechModel = .ready
                self?.logger.info("Speech model ready")
            } catch {
                self?.speechModel = .unavailable(error.localizedDescription)
                self?.logger.error("Speech warm-up failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        warmUpTask = task
        await task.value
        warmUpTask = nil
    }

    // MARK: - Pipeline

    func toggle() async {
        if state.isCapturing {
            await stop()
        } else if state.canStart {
            await start()
        }
    }

    func start() async {
        guard state.canStart else { return }

        let preferences = preferencesProvider()
        guard preferences.isWritingConfigurationValid else {
            fail(with: .customInstructionsMissing)
            return
        }

        // Claim the session before the first suspension point, so a second
        // start request arriving while this one is waiting is refused.
        let sessionID = UUID()
        self.sessionID = sessionID
        state = .requestingPermission
        result = nil
        transcript = TranscriptionUpdate()
        voiceMeter = .silent
        didReceiveAudio = false
        lastMeterPublish = nil

        await abandonActiveWork(reason: "starting new session", keeping: sessionID)
        guard self.sessionID == sessionID else { return }

        logger.info("Session \(sessionID.uuidString, privacy: .public) requesting permissions")

        // Only the microphone is essential. The on-device transcriber does not
        // depend on the legacy Speech Recognition grant, so a "no" there must not
        // block dictation; if it ever does matter, the recogniser reports it.
        let microphone = await permissions.requestMicrophone()
        microphonePermission = microphone
        guard self.sessionID == sessionID else { return }
        guard microphone.isGranted else {
            fail(with: .microphonePermissionDenied)
            return
        }
        speechPermission = await permissions.requestSpeech()
        guard self.sessionID == sessionID else { return }

        do {
            let analysisFormat = try await recognizer.prepare(locale: .current)
            logger.info(
                "Session \(sessionID.uuidString, privacy: .public) recognizer ready (format \(analysisFormat?.sampleRate ?? 0, privacy: .public) Hz)"
            )

            // The microphone opens while the model finishes loading. Audio is
            // buffered by the recogniser, so the first words are never clipped
            // however long loading takes.
            await recognizer.setVocabulary(preferences.vocabularyTerms)
            async let startedUpdates = recognizer.start()
            let chunks = try await audioCapture.start(convertingTo: analysisFormat)
            audioPumpTask = makeAudioPump(chunks: chunks, sessionID: sessionID)
            let updates = try await startedUpdates

            guard self.sessionID == sessionID else {
                // Cancelled while starting: the microphone may have opened after
                // the cancel already ran, so close it here.
                if state == .idle { await abandonActiveWork(reason: "cancelled during start") }
                return
            }
            transcriptTask = makeTranscriptTask(updates: updates, sessionID: sessionID)

            state = .listening
            logger.info("Session \(sessionID.uuidString, privacy: .public) listening")
            playIfEnabled(.start, preferences: preferences)
        } catch {
            guard self.sessionID == sessionID else { return }
            await abandonActiveWork(reason: "start failed", keeping: sessionID)
            fail(with: Self.dictationError(from: error))
        }
    }

    func stop() async {
        guard state.isCapturing else { return }

        let sessionID = self.sessionID
        let preferences = preferencesProvider()
        state = .transcribing
        logger.info("Session \(sessionID.uuidString, privacy: .public) stopping → transcribing")
        playIfEnabled(.stop, preferences: preferences)

        await teardownCapture()

        // A recogniser error here must not cost the user what was already heard.
        var recognitionError: DictationError?
        do {
            try await recognizer.finish()
        } catch {
            recognitionError = Self.dictationError(from: error)
            logger.error(
                "Session \(sessionID.uuidString, privacy: .public) recogniser finish failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        await transcriptTask?.value
        transcriptTask = nil

        // Finish tears down the recogniser so the next start cannot inherit
        // leftover audio context from a lingering model.
        await recognizer.cancel()

        guard self.sessionID == sessionID else {
            logger.notice("Session \(sessionID.uuidString, privacy: .public) discarded after stop (superseded)")
            return
        }

        let rawTranscript = transcript.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info(
            "Session \(sessionID.uuidString, privacy: .public) raw transcript (\(rawTranscript.count, privacy: .public) chars, audio=\(self.didReceiveAudio, privacy: .public))"
        )
        guard !rawTranscript.isEmpty else {
            if let recognitionError {
                fail(with: recognitionError)
            } else if !didReceiveAudio {
                fail(with: .audioCaptureFailed(
                    "Dictora couldn't hear the microphone. Check the input device and try again."
                ))
            } else {
                fail(with: .nothingHeard)
            }
            return
        }

        state = .processing
        var warning: String? = recognitionError.map { _ in
            "Speech recognition ended unexpectedly; this is what was heard so far."
        }
        let processed: ProcessedText
        do {
            processed = try await textProcessing.process(
                TextProcessingRequest(transcript: rawTranscript, preferences: preferences)
            )
        } catch {
            // The words were heard correctly; only the polish failed. Deliver
            // them as dictated rather than reporting a failure.
            logger.error(
                "Session \(sessionID.uuidString, privacy: .public) rewrite failed, delivering raw transcript: \(error.localizedDescription, privacy: .public)"
            )
            warning = "Rewriting failed, so this is exactly what you said."
            processed = ProcessedText(text: rawTranscript, processor: .localFallback)
        }
        guard self.sessionID == sessionID else { return }

        let finished = DictationResult(
            rawTranscript: rawTranscript,
            polishedText: processed.text,
            style: preferences.selectedWritingStyle,
            strength: preferences.transformationStrength,
            processor: processed.processor,
            warning: warning
        )
        result = finished
        history.insert(finished, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }

        state = .completed
        logger.info(
            "Session \(sessionID.uuidString, privacy: .public) completed (\(processed.text.count, privacy: .public) chars)"
        )
        playIfEnabled(.complete, preferences: preferences)
    }

    /// Abandons the current dictation without producing a result.
    func cancel() async {
        await abandonActiveWork(reason: "cancelled")
        transcript = TranscriptionUpdate()
        result = nil
        voiceMeter = .silent
        didReceiveAudio = false
        state = .idle
    }

    /// Clears a finished or failed run so the UI returns to its resting state.
    func reset() {
        guard !state.isBusy else { return }
        transcript = TranscriptionUpdate()
        result = nil
        voiceMeter = .silent
        didReceiveAudio = false
        state = .idle
    }

    // MARK: - Private

    private func makeAudioPump(chunks: AsyncStream<AudioChunk>, sessionID: UUID) -> Task<Void, Never> {
        Task { [weak self, recognizer] in
            var chunkCount = 0
            for await chunk in chunks {
                guard let self, self.sessionID == sessionID else { continue }
                self.didReceiveAudio = true
                chunkCount += 1
                self.publishVoiceMeter(from: chunk.buffer)
                if chunkCount == 1 || chunkCount % 100 == 0 {
                    self.logger.debug(
                        "Session \(sessionID.uuidString, privacy: .public) audio chunks=\(chunkCount, privacy: .public)"
                    )
                }
                await recognizer.append(chunk)
            }
            guard let self, self.sessionID == sessionID else { return }
            self.voiceMeter = .silent
            self.logger.info(
                "Session \(sessionID.uuidString, privacy: .public) audio stream ended after \(chunkCount, privacy: .public) chunks"
            )
            // The stream ends on its own only when the microphone went away.
            // A normal stop moves the state off `.listening` first.
            if self.state == .listening {
                self.logger.notice("Microphone stopped delivering audio mid-session")
                self.onCaptureInterrupted?()
            }
        }
    }

    private func makeTranscriptTask(
        updates: AsyncThrowingStream<TranscriptionUpdate, any Error>,
        sessionID: UUID
    ) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                for try await update in updates {
                    guard let self, self.sessionID == sessionID else { continue }
                    self.transcript = update
                }
            } catch {
                guard let self, self.sessionID == sessionID else { return }
                // Keep the session alive if words exist: `stop()` will deliver
                // them. Only fail outright when there is nothing to save.
                if self.transcript.isEmpty {
                    self.fail(with: Self.dictationError(from: error))
                } else {
                    self.logger.error(
                        "Transcript stream failed after partial results: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }

    /// Publishes meter updates at ~30 Hz so the overlay can track pitch/volume
    /// without flooding the observation loop on every audio buffer.
    private func publishVoiceMeter(from buffer: AVAudioPCMBuffer) {
        let now = ContinuousClock.now
        if let lastMeterPublish, now - lastMeterPublish < .milliseconds(33) {
            return
        }
        lastMeterPublish = now
        let reading = VoiceMeterAnalyzer.analyze(buffer)
        // Light smoothing so bars feel musical rather than noisy.
        let previous = voiceMeter
        let smoothedBands = zip(previous.bands, reading.bands).map { old, new in
            old * 0.35 + new * 0.65
        }
        voiceMeter = VoiceMeterReading(
            level: previous.level * 0.35 + reading.level * 0.65,
            bands: smoothedBands.isEmpty ? reading.bands : smoothedBands
        )
    }

    /// Cancels capture, transcript pump, and recogniser so no prior session can
    /// keep writing transcript / results into a newer one.
    ///
    /// - Parameter keeping: The session that is being started; it keeps its ID.
    private func abandonActiveWork(reason: String, keeping newSession: UUID? = nil) async {
        // Let any cleanup left behind by a failed session finish first.
        let pendingCleanup = cleanupTask
        cleanupTask = nil
        await pendingCleanup?.value

        if newSession == nil { sessionID = UUID() }
        logger.debug("Abandoning active work (\(reason, privacy: .public))")
        await teardownCapture()
        transcriptTask?.cancel()
        await transcriptTask?.value
        transcriptTask = nil
        await recognizer.cancel()
    }

    private func teardownCapture() async {
        await audioCapture.stop()
        await audioPumpTask?.value
        audioPumpTask = nil
    }

    private func fail(with error: DictationError) {
        let failedSession = sessionID
        logger.error(
            "Session \(failedSession.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)"
        )
        state = .failed(error)
        voiceMeter = .silent

        // Stop mic / recogniser so a failed session cannot keep streaming old
        // partials into the next attempt. The next `start()` awaits this task,
        // and each step re-checks the session, so it cannot touch newer work.
        cleanupTask = Task { [weak self] in
            guard let self, self.sessionID == failedSession else { return }
            await self.teardownCapture()
            guard self.sessionID == failedSession else { return }
            self.transcriptTask?.cancel()
            await self.transcriptTask?.value
            self.transcriptTask = nil
            guard self.sessionID == failedSession else { return }
            await self.recognizer.cancel()
        }
    }

    private func playIfEnabled(_ cue: SoundFeedback.Cue, preferences: UserPreferences) {
        guard preferences.playSounds else { return }
        soundFeedback.play(cue)
    }

    private static func dictationError(from error: any Error) -> DictationError {
        switch error {
        case let error as DictationError:
            return error
        case let error as SpeechRecognitionError:
            switch error {
            case .unsupportedOnThisSystem, .localeNotSupported, .modelAssetsUnavailable:
                return .speechRecognitionUnavailable(error.localizedDescription)
            case .notPrepared, .failed:
                return .transcriptionFailed(error.localizedDescription)
            }
        case let error as AudioCaptureError:
            return .audioCaptureFailed(error.localizedDescription)
        case let error as TextProcessingError:
            if case .missingCustomInstructions = error { return .customInstructionsMissing }
            return .textProcessingFailed(error.localizedDescription)
        default:
            return .transcriptionFailed(error.localizedDescription)
        }
    }
}
