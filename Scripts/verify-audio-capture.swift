#!/usr/bin/env swift
//
// Verifies the two properties AudioCaptureService depends on, using the same
// API sequence it does:
//
//   1. Microphone capture delivers PCM that converts to the transcriber's
//      format. If this breaks, dictation silently produces nothing.
//   2. Capturing never opens the *output* device. An AVAudioEngine starts its
//      whole graph, output node included, so it holds the speakers open even
//      for an app that plays nothing — which makes other audio on the Mac drop
//      into the thin, processed sound you get on a call. AVCaptureSession is
//      capture-only, and this script is what proves it stays that way.
//
// Usage:
//   ./Scripts/verify-audio-capture.swift
//
// Records nothing: buffers are counted and discarded.
//
// The equivalent checks live in Tests/AudioCaptureServiceTests.swift, but they
// skip unless the test host itself has been granted microphone access, which is
// often not the case. This script runs under the terminal's own grant instead.

import AVFoundation
import CoreAudio
import CoreMedia

let captureSeconds = 3.0
let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

func defaultOutputDevice() -> AudioDeviceID {
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

func isRunning(_ id: AudioDeviceID) -> Bool {
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

/// Mirrors SampleBufferForwarder in AudioCaptureService.
final class Forwarder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private(set) var rawBuffers = 0
    private(set) var convertedBuffers = 0
    private(set) var failures = 0
    private(set) var convertedFrames = 0
    private(set) var sourceFormat = "unknown"
    private var converter: AVAudioConverter?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard
            let description = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
            let format = AVAudioFormat(streamDescription: streamDescription)
        else { failures += 1; return }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            failures += 1; return
        }
        buffer.frameLength = frames

        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        ) == noErr else { failures += 1; return }

        rawBuffers += 1
        sourceFormat = "\(Int(format.sampleRate)) Hz, \(format.channelCount) ch"

        if converter == nil {
            converter = AVAudioConverter(from: format, to: target)
            converter?.primeMethod = .none
        }
        guard let converter else { failures += 1; return }

        let ratio = target.sampleRate / format.sampleRate
        let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 1024
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            failures += 1; return
        }

        var pending: AVAudioPCMBuffer? = buffer
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            guard let next = pending else { status.pointee = .noDataNow; return nil }
            pending = nil
            status.pointee = .haveData
            return next
        }
        if error != nil { failures += 1; return }

        convertedBuffers += 1
        convertedFrames += Int(converted.frameLength)
    }
}

guard let device = AVCaptureDevice.default(for: .audio) else {
    print("error: no audio capture device")
    exit(1)
}

let session = AVCaptureSession()
let input = try AVCaptureDeviceInput(device: device)
let output = AVCaptureAudioDataOutput()
output.audioSettings = [AVFormatIDKey: Int(kAudioFormatLinearPCM)]
let forwarder = Forwarder()
output.setSampleBufferDelegate(forwarder, queue: DispatchQueue(label: "verify-audio-capture"))

session.beginConfiguration()
guard session.canAddInput(input), session.canAddOutput(output) else {
    print("error: could not build the capture session")
    exit(1)
}
session.addInput(input)
session.addOutput(output)
session.commitConfiguration()

let speakers = defaultOutputDevice()
let speakersBusyBefore = isRunning(speakers)

session.startRunning()
var speakersOpened = false
let deadline = Date().addingTimeInterval(captureSeconds)
while Date() < deadline {
    Thread.sleep(forTimeInterval: 0.05)
    if isRunning(speakers) { speakersOpened = true }
}
session.stopRunning()

let seconds = Double(forwarder.convertedFrames) / target.sampleRate

print("microphone        \(device.localizedName)")
print("source format     \(forwarder.sourceFormat)")
print("raw buffers       \(forwarder.rawBuffers)")
print("converted to 16k  \(forwarder.convertedBuffers) buffers, \(String(format: "%.1f", seconds))s of audio")
print("failures          \(forwarder.failures)")
print("")

var ok = true

if forwarder.rawBuffers > 0, forwarder.convertedBuffers > 0, forwarder.failures == 0 {
    print("PASS  audio flows and converts to the transcriber's format")
} else {
    print("FAIL  audio did not flow cleanly (check microphone permission for your terminal)")
    ok = false
}

if speakersBusyBefore {
    print("SKIP  something else was already playing, so the speaker check is inconclusive")
} else if speakersOpened {
    print("FAIL  capture opened the output device — other audio on this Mac will degrade")
    ok = false
} else {
    print("PASS  capture left the output device closed")
}

exit(ok ? 0 : 1)
