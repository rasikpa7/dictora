import AVFoundation
import Foundation
import OSLog

/// One buffer of microphone audio.
///
/// `AVAudioPCMBuffer` is not `Sendable`. Each chunk here wraps a buffer that was
/// freshly allocated by the format converter and is handed off exactly once, so
/// no two threads ever see the same instance.
struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

enum AudioCaptureError: LocalizedError, Equatable, Sendable {
    case engineUnavailable(String)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .engineUnavailable(let detail): detail
        case .unsupportedFormat: "The microphone's audio format isn't supported."
        }
    }
}

/// Microphone capture, decoupled from whatever consumes the audio.
protocol AudioCapturing: Sendable {
    /// Starts the engine and returns a stream of buffers already converted to
    /// `outputFormat` (or the raw microphone format when it is `nil`).
    func start(convertingTo outputFormat: AVAudioFormat?) async throws -> AsyncStream<AudioChunk>
    func stop() async
}

/// `AVAudioEngine`-backed capture.
///
/// Implemented as an actor so the engine, tap and stream continuation are only
/// ever touched from one isolation domain; the render-thread tap is the single
/// documented exception below.
actor AudioCaptureService: AudioCapturing {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var isCapturing = false
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "AudioCapture")

    private static let tapBufferSize: AVAudioFrameCount = 4096

    init() {}

    func start(convertingTo outputFormat: AVAudioFormat?) async throws -> AsyncStream<AudioChunk> {
        if isCapturing { stop() }

        #if os(iOS)
        try configureAudioSession()
        #endif

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.unsupportedFormat
        }

        let converter = try outputFormat.map { try BufferConverter(from: inputFormat, to: $0) }
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.continuation = continuation

        // The tap runs on the real-time audio thread. It only touches the
        // continuation (which is Sendable) and the converter, which nothing
        // else uses for the lifetime of the tap.
        inputNode.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: inputFormat) { buffer, _ in
            guard let converter else {
                continuation.yield(AudioChunk(buffer: buffer))
                return
            }
            if let converted = try? converter.convert(buffer) {
                continuation.yield(AudioChunk(buffer: converted))
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            continuation.finish()
            self.continuation = nil
            throw AudioCaptureError.engineUnavailable(error.localizedDescription)
        }

        isCapturing = true
        logger.debug("Audio capture started at \(inputFormat.sampleRate, privacy: .public) Hz")
        return stream
    }

    func stop() {
        guard isCapturing else { return }
        isCapturing = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil

        #if os(iOS)
        deactivateAudioSession()
        #endif
        logger.debug("Audio capture stopped")
    }

    #if os(iOS)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw AudioCaptureError.engineUnavailable(error.localizedDescription)
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

/// Converts microphone buffers into the format the transcriber asked for.
///
/// Marked `@unchecked Sendable` because `AVAudioConverter` is not thread-safe
/// but is confined to a single audio tap, which the system serialises.
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
            throw AudioCaptureError.engineUnavailable(conversionError.localizedDescription)
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
