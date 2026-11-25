import AVFoundation
import CoreMedia
import Foundation
import OSLog

#if os(macOS)
import CoreAudio
#endif

/// One buffer of microphone audio.
///
/// `AVAudioPCMBuffer` is not `Sendable`. Each chunk here wraps a buffer that was
/// freshly allocated for this chunk alone and is handed off exactly once, so no
/// two threads ever see the same instance.
struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

enum AudioCaptureError: LocalizedError, Equatable, Sendable {
    case captureUnavailable(String)
    case microphoneUnavailable
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .captureUnavailable(let detail): detail
        case .microphoneUnavailable: "No microphone is available on this device."
        case .unsupportedFormat: "The microphone's audio format isn't supported."
        }
    }
}

/// Microphone capture, decoupled from whatever consumes the audio.
protocol AudioCapturing: Sendable {
    /// Starts capturing and returns a stream of buffers already converted to
    /// `outputFormat` (or the raw microphone format when it is `nil`).
    func start(convertingTo outputFormat: AVAudioFormat?) async throws -> AsyncStream<AudioChunk>
    func stop() async
}

/// `AVCaptureSession`-backed microphone capture.
///
/// Deliberately *not* `AVAudioEngine`. Starting an engine runs its whole graph,
/// output node included, so it opens the speakers as well as the microphone
/// even for an app like Dictora that never plays anything through it. Holding
/// the output device open makes the system re-negotiate it, which audibly
/// degrades whatever else is playing — music drops into the thin, processed
/// sound you get on a call. `AVCaptureSession` is capture-only and leaves the
/// output device untouched.
///
/// Implemented as an actor so the session and continuation are only ever
/// touched from one isolation domain; the capture queue is the single
/// documented exception below.
actor AudioCaptureService: AudioCapturing {
    private var session: AVCaptureSession?
    private var forwarder: SampleBufferForwarder?
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var interruptionObservers: [any NSObjectProtocol] = []
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "AudioCapture")

    /// Serial, so the forwarder's lazily built converter needs no locking.
    private let captureQueue = DispatchQueue(label: "com.dictora.audio-capture")

    init() {}

    func start(convertingTo outputFormat: AVAudioFormat?) async throws -> AsyncStream<AudioChunk> {
        await stop()

        #if os(iOS)
        try configureAudioSession()
        #endif

        guard let device = Self.preferredMicrophone() else {
            throw AudioCaptureError.microphoneUnavailable
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw AudioCaptureError.captureUnavailable(error.localizedDescription)
        }

        let output = AVCaptureAudioDataOutput()
        #if os(macOS)
        // Ask for linear PCM explicitly rather than relying on the default, so
        // the buffers can always be wrapped in an `AVAudioPCMBuffer`. iOS has no
        // equivalent knob and already delivers linear PCM.
        output.audioSettings = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
        ]
        #endif

        let session = AVCaptureSession()
        #if os(iOS)
        // Dictora configures the audio session itself, just above.
        session.automaticallyConfiguresApplicationAudioSession = false
        #endif

        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw AudioCaptureError.captureUnavailable("The microphone couldn't be opened for capture.")
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        // Prefer keeping early frames over dropping them — silent drops look
        // like "listening but hearing nothing".
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingOldest(96)
        )
        let forwarder = SampleBufferForwarder(
            continuation: continuation,
            outputFormat: outputFormat,
            logger: logger
        )
        output.setSampleBufferDelegate(forwarder, queue: captureQueue)

        self.session = session
        self.forwarder = forwarder
        self.continuation = continuation

        // Watch for the microphone vanishing (unplugged, Bluetooth headset
        // switching profile, another app taking over). Without this the stream
        // just goes quiet and the user finds out only at the end.
        let center = NotificationCenter.default
        interruptionObservers = [
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
                Task { await self?.handleInterruption("runtime error") }
            },
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) { [weak self] _ in
                Task { await self?.handleInterruption("microphone disconnected") }
            },
        ]

        session.startRunning()
        guard session.isRunning else {
            await stop()
            throw AudioCaptureError.captureUnavailable("The microphone couldn't be started.")
        }

        // Give Core Audio a beat to start delivering buffers before the
        // recogniser is considered "live". Avoids empty first sessions.
        try? await Task.sleep(for: .milliseconds(80))

        logger.info(
            "Audio capture started on \(device.localizedName, privacy: .public)"
        )
        return stream
    }

    func stop() {
        for observer in interruptionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        interruptionObservers = []

        guard session != nil || continuation != nil else { return }

        session?.stopRunning()
        session = nil
        forwarder = nil
        continuation?.finish()
        continuation = nil

        #if os(iOS)
        deactivateAudioSession()
        #endif
        logger.debug("Audio capture stopped")
    }

    /// Ends the stream so the consumer notices; it decides what to do next.
    private func handleInterruption(_ reason: String) {
        guard session != nil else { return }
        logger.notice("Audio capture interrupted: \(reason, privacy: .public)")
        stop()
    }

    /// Prefers the dedicated microphone device type Apple's speech samples use,
    /// then falls back to the legacy default audio device.
    private static func preferredMicrophone() -> AVCaptureDevice? {
        if let microphone = AVCaptureDevice.default(
            .microphone,
            for: .audio,
            position: .unspecified
        ) {
            return microphone
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        if let first = discovery.devices.first {
            return first
        }

        return AVCaptureDevice.default(for: .audio)
    }

    #if os(iOS)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // Measurement keeps levels closer to the raw mic; duckOthers keeps
            // Dictora audible against background audio without a voice-chat gate.
            try session.setCategory(.playAndRecord, mode: .measurement, options: [
                .duckOthers,
                .allowBluetoothHFP,
                .defaultToSpeaker,
            ])
            if session.isInputGainSettable {
                try session.setInputGain(1.0)
            }
            try session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw AudioCaptureError.captureUnavailable(error.localizedDescription)
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.debug("Audio session deactivation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
}

/// Turns capture callbacks into `AudioChunk`s on the stream.
///
/// Marked `@unchecked Sendable` because its mutable state is only ever touched
/// from the serial capture queue the delegate is installed on.
private final class SampleBufferForwarder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
                                           @unchecked Sendable {
    private let continuation: AsyncStream<AudioChunk>.Continuation
    private let outputFormat: AVAudioFormat?
    private let logger: Logger
    /// Built from the first buffer: unlike an audio engine, a capture session
    /// does not report its format until audio actually starts flowing.
    private var converter: BufferConverter?
    private var consecutiveConversionFailures = 0
    private var hasLoggedConversionFailure = false

    init(
        continuation: AsyncStream<AudioChunk>.Continuation,
        outputFormat: AVAudioFormat?,
        logger: Logger
    ) {
        self.continuation = continuation
        self.outputFormat = outputFormat
        self.logger = logger
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = Self.makePCMBuffer(from: sampleBuffer) else { return }

        let delivered: AVAudioPCMBuffer?
        if let outputFormat {
            if converter == nil {
                do {
                    converter = try BufferConverter(from: buffer.format, to: outputFormat)
                } catch {
                    consecutiveConversionFailures += 1
                    if !hasLoggedConversionFailure {
                        hasLoggedConversionFailure = true
                        logger.error(
                            "Audio format conversion unavailable (\(buffer.format.sampleRate, privacy: .public) Hz → \(outputFormat.sampleRate, privacy: .public) Hz): \(error.localizedDescription, privacy: .public)"
                        )
                    }
                    // Do not feed the raw mic format into the analyzer — wrong
                    // formats are accepted silently and produce empty transcripts.
                    return
                }
            }

            guard let converter else { return }

            do {
                delivered = try converter.convert(buffer)
                consecutiveConversionFailures = 0
            } catch {
                consecutiveConversionFailures += 1
                if consecutiveConversionFailures == 1 || consecutiveConversionFailures % 50 == 0 {
                    logger.error(
                        "Audio buffer conversion failed (\(self.consecutiveConversionFailures, privacy: .public)x): \(error.localizedDescription, privacy: .public)"
                    )
                }
                return
            }
        } else {
            delivered = buffer
        }

        guard let delivered else { return }
        continuation.yield(AudioChunk(buffer: delivered))
    }

    private static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
            let format = AVAudioFormat(streamDescription: streamDescription)
        else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }
}

/// Converts microphone buffers into the format the transcriber asked for.
///
/// Marked `@unchecked Sendable` because `AVAudioConverter` is not thread-safe
/// but is confined to the serial capture queue.
private final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.unsupportedFormat
        }
        converter.primeMethod = .none
        self.converter = converter
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw AudioCaptureError.unsupportedFormat
        }

        // `AVAudioConverterInputBlock` is declared `@Sendable`, so the input
        // buffer and the "already supplied" flag are boxed together rather than
        // captured directly. The box never leaves this synchronous call.
        let input = ConversionInput(buffer: buffer)
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            guard let next = input.take() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return next
        }

        if let conversionError {
            throw AudioCaptureError.captureUnavailable(conversionError.localizedDescription)
        }
        guard output.frameLength > 0 else {
            throw AudioCaptureError.unsupportedFormat
        }
        return output
    }
}

/// Single-use holder handing one microphone buffer to `AVAudioConverter`.
private final class ConversionInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
