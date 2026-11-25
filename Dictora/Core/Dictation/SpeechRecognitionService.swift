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
    private var analysisFormat: AVAudioFormat?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var reservedLocale: Locale?
    private var vocabulary: [String] = []
    /// Bumps on every prepare/cancel so a stale results task cannot finish a newer session.
    private var sessionGeneration = UUID()

    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "SpeechRecognition")

    init() {}

    deinit {
        resultsTask?.cancel()
        inputContinuation?.finish()
    }

    func warmUp(locale: Locale, onProgress: @escaping @Sendable (Double?) -> Void) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw SpeechRecognitionError.unsupportedOnThisSystem
        }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechRecognitionError.localeNotSupported(locale.identifier)
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .progressiveTranscription)
        try await installAssetsIfNeeded(for: transcriber, locale: supportedLocale, onProgress: onProgress)

        // Load the model into memory now. With process-lifetime retention the
        // analyzers created for real sessions reuse it instead of loading again.
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .utility, modelRetention: .processLifetime)
        )
        try? await analyzer.prepareToAnalyze(in: format)
        logger.info("Speech model warmed up for \(supportedLocale.identifier, privacy: .public)")
    }

    func setVocabulary(_ terms: [String]) {
        vocabulary = terms
    }

    func prepare(locale: Locale) async throws -> AVAudioFormat? {
        await teardown()
        sessionGeneration = UUID()

        guard SpeechTranscriber.isAvailable else {
            throw SpeechRecognitionError.unsupportedOnThisSystem
        }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechRecognitionError.localeNotSupported(locale.identifier)
        }

        // Progressive + volatile results so text appears while the user is still
        // speaking. Empty option sets omit the progressive preset and are less
        // reliable for live dictation.
        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            preset: .progressiveTranscription
        )

        try await installAssetsIfNeeded(for: transcriber, locale: supportedLocale)

        self.transcriber = transcriber
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        self.analysisFormat = format
        return format
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, any Error> {
        guard let transcriber else { throw SpeechRecognitionError.notPrepared }
        let generation = sessionGeneration

        // Lossless for the analyzer: dropping newest frames under load produces
        // silent "nothing heard" sessions. Prefer back-pressure over silence.
        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingOldest(192)
        )
        self.inputContinuation = inputContinuation

        // Each session gets a fresh analyzer, so no audio context carries over;
        // only the loaded model is kept, which makes starting fast.
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .processLifetime)
        )
        self.analyzer = analyzer

        do {
            if !vocabulary.isEmpty {
                // Biases recognition toward the user's names and terms, so
                // "Claude" is not heard as "cloud".
                let context = AnalysisContext()
                context.contextualStrings[.general] = vocabulary
                try await analyzer.setContext(context)
            }
            // Without this, the first session after launch (and sometimes later
            // cold starts) can accept audio while the model is still loading —
            // UI shows Listening, but nothing is transcribed until restart.
            try await analyzer.prepareToAnalyze(in: analysisFormat)
            try await analyzer.start(inputSequence: inputStream)
            logger.info("Speech analyzer started (generation \(generation.uuidString, privacy: .public))")
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
                    let currentGeneration = await self.sessionGeneration
                    guard generation == currentGeneration else { break }
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
        guard let inputContinuation else { return }
        let yieldResult = inputContinuation.yield(AnalyzerInput(buffer: chunk.buffer))
        if case .terminated = yieldResult {
            logger.error("Speech analyzer input stream terminated while audio was still arriving")
        }
    }

    func finish() async throws {
        logger.info("Speech analyzer finishing (generation \(self.sessionGeneration.uuidString, privacy: .public))")
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
        // Drop the transcriber so the next prepare() cannot see prior results.
        transcriber = nil
        analysisFormat = nil
    }

    func cancel() async {
        await teardown()
    }

    // MARK: - Private

    private func teardown() async {
        sessionGeneration = UUID()

        inputContinuation?.finish()
        inputContinuation = nil

        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        analyzer = nil
        analysisFormat = nil

        resultsTask?.cancel()
        resultsTask = nil
        transcriber = nil
        // The locale reservation is kept on purpose: releasing and re-reserving
        // it on every dictation is slow and gains nothing.
    }

    /// Downloads the locale's on-device model if it is missing.
    ///
    /// Reservation can legitimately fail when the user already has the maximum
    /// number of locales reserved system-wide; that is not fatal for a single
    /// dictation, so it is logged rather than thrown.
    private func installAssetsIfNeeded(
        for transcriber: SpeechTranscriber,
        locale: Locale,
        onProgress: (@Sendable (Double?) -> Void)? = nil
    ) async throws {
        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }

        if !isInstalled {
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    logger.info("Downloading speech assets for \(locale.identifier, privacy: .public)")
                    onProgress?(nil)
                    let progress = request.progress
                    let observation = progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                        onProgress?(progress.fractionCompleted)
                    }
                    defer { observation.invalidate() }
                    try await request.downloadAndInstall()
                }
            } catch {
                throw SpeechRecognitionError.modelAssetsUnavailable(
                    "Dictora couldn't download the speech model for \(locale.identifier). \(error.localizedDescription)"
                )
            }
        }

        guard reservedLocale?.identifier(.bcp47) != locale.identifier(.bcp47) else { return }
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
