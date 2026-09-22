import AVFoundation
import Foundation
import OSLog
import Speech

/// Transcription built on Apple's on-device `SpeechAnalyzer` stack (macOS 26 / iOS 26).
///
/// An actor because it owns a live analysis session: the analyzer, the audio
/// input continuation and the results task must not be driven concurrently.
@available(macOS 26.0, iOS 26.0, *)
actor SpeechRecognitionService: SpeechRecognizing {
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var reservedLocale: Locale?

    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "SpeechRecognition")

    init() {}

    deinit {
        resultsTask?.cancel()
        inputContinuation?.finish()
    }

    func prepare(locale: Locale) async throws -> AVAudioFormat? {
        await teardown()

        guard SpeechTranscriber.isAvailable else {
            throw SpeechRecognitionError.unsupportedOnThisSystem
        }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechRecognitionError.localeNotSupported(locale.identifier)
        }

        // `.volatileResults` is what makes text appear while the user is still
        // speaking; without it nothing is emitted until finalization.
        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        try await installAssetsIfNeeded(for: transcriber, locale: supportedLocale)

        self.transcriber = transcriber
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, any Error> {
        guard let transcriber else { throw SpeechRecognitionError.notPrepared }

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(128)
        )
        self.inputContinuation = inputContinuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        do {
            try await analyzer.start(inputSequence: inputStream)
        } catch {
            inputContinuation.finish()
            self.inputContinuation = nil
            self.analyzer = nil
            throw SpeechRecognitionError.failed(error.localizedDescription)
        }

        let (updates, updatesContinuation) = AsyncThrowingStream<TranscriptionUpdate, any Error>.makeStream()

        resultsTask = Task {
            var finalized = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized = Self.join(finalized, text)
                        updatesContinuation.yield(TranscriptionUpdate(finalizedText: finalized))
                    } else {
                        updatesContinuation.yield(
                            TranscriptionUpdate(finalizedText: finalized, volatileText: text)
                        )
                    }
                }
                updatesContinuation.finish()
            } catch {
                updatesContinuation.finish(throwing: SpeechRecognitionError.failed(error.localizedDescription))
            }
        }

        return updates
    }

    func append(_ chunk: AudioChunk) {
        inputContinuation?.yield(AnalyzerInput(buffer: chunk.buffer))
    }

    func finish() async throws {
        inputContinuation?.finish()
        inputContinuation = nil

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            throw SpeechRecognitionError.failed(error.localizedDescription)
        }

        // Wait for the results task to drain so callers observe every final result.
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
    }

    func cancel() async {
        await teardown()
    }

    // MARK: - Private

    private func teardown() async {
        inputContinuation?.finish()
        inputContinuation = nil

        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        analyzer = nil

        resultsTask?.cancel()
        resultsTask = nil
        transcriber = nil

        if let reservedLocale {
            await AssetInventory.release(reservedLocale: reservedLocale)
            self.reservedLocale = nil
        }
    }

    /// Downloads the locale's on-device model if it is missing.
    ///
    /// Reservation can legitimately fail when the user already has the maximum
    /// number of locales reserved system-wide; that is not fatal for a single
    /// dictation, so it is logged rather than thrown.
    private func installAssetsIfNeeded(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }

        if !isInstalled {
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    logger.info("Downloading speech assets for \(locale.identifier, privacy: .public)")
                    try await request.downloadAndInstall()
                }
            } catch {
                throw SpeechRecognitionError.modelAssetsUnavailable(
                    "Dictora couldn't download the speech model for \(locale.identifier). \(error.localizedDescription)"
                )
            }
        }

        do {
            try await AssetInventory.reserve(locale: locale)
            reservedLocale = locale
        } catch {
            logger.notice("Could not reserve locale: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func join(_ existing: String, _ addition: String) -> String {
        let trimmedAddition = addition.trimmingCharacters(in: .whitespaces)
        guard !trimmedAddition.isEmpty else { return existing }
        guard !existing.isEmpty else { return trimmedAddition }
        return existing + " " + trimmedAddition
    }
}

/// Chooses the best recogniser the running OS can provide.
enum SpeechRecognizerFactory {
    static func makeDefault() -> any SpeechRecognizing {
        if #available(macOS 26.0, iOS 26.0, *) {
            SpeechRecognitionService()
        } else {
            UnsupportedSpeechRecognizer()
        }
    }
}
