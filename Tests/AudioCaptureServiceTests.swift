import AVFoundation
import CoreAudio
import Foundation
import Testing

#if os(macOS)
@testable import DictoraMac
#else
@testable import DictoraiOS
#endif

#if os(macOS)
/// Reads whether CoreAudio currently has the default output device running.
///
/// This is how the "capture must not touch the speakers" rule is checked: an
/// `AVAudioEngine` starts its whole graph, output node included, so it opens the
/// output device even for an app that never plays anything. Holding the
/// speakers open makes the system re-negotiate them and audibly degrades other
/// playback, so a regression here is not cosmetic.
private enum AudioDeviceProbe {
    static var defaultOutputDevice: AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    static func isRunning(_ id: AudioDeviceID) -> Bool {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value != 0
    }
}

private var microphoneIsUsable: Bool {
    AVCaptureDevice.default(for: .audio) != nil
        && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
}

@Suite("Audio capture", .serialized)
struct AudioCaptureServiceTests {
    /// The format `SpeechAnalyzer` typically asks for.
    private var analysisFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    }

    @Test(
        "Capturing the microphone never opens the speakers",
        // The probe needs a silent output device, so it is skipped (not failed)
        // when something else on the Mac is playing audio.
        .enabled(if: microphoneIsUsable && !AudioDeviceProbe.isRunning(AudioDeviceProbe.defaultOutputDevice))
    )
    func captureLeavesOutputDeviceAlone() async throws {
        let speakers = AudioDeviceProbe.defaultOutputDevice
        try #require(!AudioDeviceProbe.isRunning(speakers), "Something is already playing audio")

        let service = AudioCaptureService()
        let stream = try await service.start(convertingTo: analysisFormat)

        var openedSpeakers = false
        let consumer = Task {
            var seen = 0
            for await _ in stream {
                seen += 1
                if seen >= 8 { break }
            }
            return seen
        }

        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(50))
            if AudioDeviceProbe.isRunning(speakers) { openedSpeakers = true }
        }

        consumer.cancel()
        await service.stop()

        #expect(!openedSpeakers, "Capture opened the output device — see AudioCaptureService")
    }

    @Test(
        "Captured audio arrives in the format the transcriber asked for",
        // The probe needs a silent output device, so it is skipped (not failed)
        // when something else on the Mac is playing audio.
        .enabled(if: microphoneIsUsable && !AudioDeviceProbe.isRunning(AudioDeviceProbe.defaultOutputDevice))
    )
    func captureDeliversRequestedFormat() async throws {
        let format = analysisFormat
        let service = AudioCaptureService()
        let stream = try await service.start(convertingTo: format)

        let collector = Task { () -> [AVAudioFormat] in
            var formats: [AVAudioFormat] = []
            for await chunk in stream {
                formats.append(chunk.buffer.format)
                if formats.count >= 5 { break }
            }
            return formats
        }

        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            collector.cancel()
        }
        let formats = await collector.value
        timeout.cancel()
        await service.stop()

        try #require(!formats.isEmpty, "No audio was delivered")
        #expect(formats.allSatisfy { $0.sampleRate == format.sampleRate })
        #expect(formats.allSatisfy { $0.channelCount == format.channelCount })
    }

    @Test("Stopping without starting is harmless")
    func stopWithoutStartIsSafe() async {
        let service = AudioCaptureService()
        await service.stop()
        await service.stop()
    }
}
#endif
