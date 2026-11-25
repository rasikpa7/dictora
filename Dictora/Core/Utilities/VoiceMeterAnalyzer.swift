import Accelerate
import AVFoundation
import Foundation

/// Live mic energy for the floating voice bars.
///
/// `level` is overall loudness; `bands` are low→high frequency buckets so the
/// bars react to both volume and pitch/timbre, not a fake sine wave.
struct VoiceMeterReading: Equatable, Sendable {
    var level: Float
    var bands: [Float]

    static let bandCount = 7
    static let silent = VoiceMeterReading(
        level: 0,
        bands: Array(repeating: 0, count: bandCount)
    )
}

enum VoiceMeterAnalyzer {
    /// Builds a meter reading from a PCM buffer.
    ///
    /// Uses RMS for loudness and a small real FFT so each bar tracks a
    /// different frequency band (low pitch → left, higher → right).
    static func analyze(_ buffer: AVAudioPCMBuffer) -> VoiceMeterReading {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 16 else { return .silent }

        let samples = monoSamples(from: buffer, frameCount: frameCount)
        guard !samples.isEmpty else { return .silent }

        let level = normalizedRMS(samples)
        let bands = frequencyBands(samples, count: VoiceMeterReading.bandCount, overallLevel: level)
        return VoiceMeterReading(level: level, bands: bands)
    }

    // MARK: - Private

    private static func monoSamples(from buffer: AVAudioPCMBuffer, frameCount: Int) -> [Float] {
        if let channels = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            if channelCount == 1 {
                return Array(UnsafeBufferPointer(start: channels[0], count: frameCount))
            }
            var mono = [Float](repeating: 0, count: frameCount)
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channels[channel][frame]
                }
                mono[frame] = sum / Float(channelCount)
            }
            return mono
        }

        if let channels = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)
            let scale: Float = 1 / Float(Int16.max)
            var mono = [Float](repeating: 0, count: frameCount)
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += Float(channels[channel][frame]) * scale
                }
                mono[frame] = sum / Float(max(channelCount, 1))
            }
            return mono
        }

        return []
    }

    private static func normalizedRMS(_ samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        // Raw microphone speech sits well below 1.0; scale into a usable UI range.
        // Room noise and mic hiss sit just above zero; gate them out so the bars
        // stay flat until someone actually speaks.
        let gated = max(0, rms - 0.006)
        let boosted = min(1, gated * 22)
        // Gentle curve so quiet speech still moves the bars.
        return pow(boosted, 0.65)
    }

    private static func frequencyBands(_ samples: [Float], count: Int, overallLevel: Float) -> [Float] {
        let n = 1 << Int(log2(Float(samples.count)))
        guard n >= 64 else {
            return Array(repeating: overallLevel, count: count)
        }

        let input = Array(samples.prefix(n))
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(n))

        let log2n = vDSP_Length(log2(Float(n)))
        guard let setup = FFTSetupCache.setup(for: log2n) else {
            return Array(repeating: overallLevel, count: count)
        }

        let half = n / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        // The split-complex struct only holds raw pointers, so every use of it
        // stays inside the scope that keeps the arrays' storage alive.
        real.withUnsafeMutableBufferPointer { realBuffer in
            imag.withUnsafeMutableBufferPointer { imagBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                windowed.withUnsafeBufferPointer { samplesBuffer in
                    samplesBuffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // Skip DC; map remaining bins onto `count` log-ish bands.
        let usable = Array(magnitudes.dropFirst().prefix(max(half - 1, 1)))
        guard !usable.isEmpty else { return Array(repeating: overallLevel, count: count) }

        var bands = [Float](repeating: 0, count: count)
        for band in 0..<count {
            // Logarithmic spacing: low frequencies get fewer bins visually weighted.
            let startFraction = pow(Float(band) / Float(count), 1.55)
            let endFraction = pow(Float(band + 1) / Float(count), 1.55)
            let start = Int(startFraction * Float(usable.count))
            let end = max(start + 1, Int(endFraction * Float(usable.count)))
            let slice = usable[start..<min(end, usable.count)]
            var mean: Float = 0
            vDSP_meanv(Array(slice), 1, &mean, vDSP_Length(slice.count))
            // Magnitude is energy²-ish; sqrt then normalize against speech levels.
            let amplitude = sqrt(max(mean, 0))
            bands[band] = min(1, pow(max(0, amplitude - 0.01) * 12, 0.55))
        }

        // Blend a little overall level in so soft speech still lifts every bar,
        // but only when there is speech to speak of.
        if overallLevel > 0.02 {
            for index in bands.indices {
                bands[index] = min(1, max(bands[index], overallLevel * 0.35))
            }
        } else {
            bands = Array(repeating: 0, count: count)
        }
        return bands
    }
}

/// FFT setups are expensive to build and the meter needs one every ~33 ms, so
/// they are created once per size and kept.
private enum FFTSetupCache {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var setups: [vDSP_Length: FFTSetup] = [:]
    }
    private static let box = Box()

    static func setup(for log2n: vDSP_Length) -> FFTSetup? {
        box.lock.withLock {
            if let existing = box.setups[log2n] { return existing }
            guard let created = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
            box.setups[log2n] = created
            return created
        }
    }
}
