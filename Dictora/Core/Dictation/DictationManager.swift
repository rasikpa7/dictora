import AVFoundation
import Foundation
import OSLog

/// Orchestrates the whole dictation pipeline:
/// audio capture → speech recognition → text processing → result.
///
/// It owns the state machine and nothing else: every step is delegated to a
/// service behind a protocol, so this type stays small and the individual
/// stages remain independently testable and replaceable.
@MainActor
@Observable
final class DictationManager {
    private(set) var state: DictationState = .idle
    private(set) var transcript = TranscriptionUpdate()
    private(set) var result: DictationResult?
    private(set) var microphonePermission: PermissionStatus = .notDetermined
    private(set) var speechPermission: PermissionStatus = .notDetermined

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

        result = nil
        transcript = TranscriptionUpdate()
        state = .requestingPermission

        guard await requestPermissions() else {
            fail(with: microphonePermission.isGranted ? .speechPermissionDenied : .microphonePermissionDenied)
            return
        }

        do {
            let analysisFormat = try await recognizer.prepare(locale: .current)
            let updates = try await recognizer.start()

            transcriptTask = Task { [weak self] in
                do {
                    for try await update in updates {
                        self?.transcript = update
                    }
                } catch {
                    self?.fail(with: Self.dictationError(from: error))
                }
            }

            let chunks = try await audioCapture.start(convertingTo: analysisFormat)
            audioPumpTask = Task { [recognizer] in
                for await chunk in chunks {
                    await recognizer.append(chunk)
                }
            }

            state = .listening
            playIfEnabled(.start, preferences: preferences)
        } catch {
            await teardownCapture()
            await recognizer.cancel()
            fail(with: Self.dictationError(from: error))
        }
    }

    func stop() async {
        guard state.isCapturing else { return }

        let preferences = preferencesProvider()
        state = .transcribing
        playIfEnabled(.stop, preferences: preferences)

        await teardownCapture()

        do {
            try await recognizer.finish()
        } catch {
            fail(with: Self.dictationError(from: error))
            return
        }
        await transcriptTask?.value
        transcriptTask = nil

        let rawTranscript = transcript.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTranscript.isEmpty else {
            fail(with: .nothingHeard)
            return
        }

        state = .processing
        do {
            let processed = try await textProcessing.process(
                TextProcessingRequest(transcript: rawTranscript, preferences: preferences)
            )
            result = DictationResult(
                rawTranscript: rawTranscript,
                polishedText: processed.text,
                style: preferences.selectedWritingStyle,
                strength: preferences.transformationStrength,
                processor: processed.processor
            )
            state = .completed
            playIfEnabled(.complete, preferences: preferences)
        } catch {
            fail(with: Self.dictationError(from: error))
        }
    }

    /// Abandons the current dictation without producing a result.
    func cancel() async {
        await teardownCapture()
        transcriptTask?.cancel()
        transcriptTask = nil
        await recognizer.cancel()
        transcript = TranscriptionUpdate()
        state = .idle
    }

    /// Clears a finished or failed run so the UI returns to its resting state.
    func reset() {
        guard !state.isBusy else { return }
        transcript = TranscriptionUpdate()
        result = nil
        state = .idle
    }

    // MARK: - Private

    private func teardownCapture() async {
        await audioCapture.stop()
        await audioPumpTask?.value
        audioPumpTask = nil
    }

    private func fail(with error: DictationError) {
        logger.error("Dictation failed: \(String(describing: error), privacy: .public)")
        state = .failed(error)
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
