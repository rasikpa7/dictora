import AVFoundation
import Foundation
import Speech

enum PermissionStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted

    var isGranted: Bool { self == .granted }

    /// True when prompting the user could still change the answer.
    var canPrompt: Bool { self == .notDetermined }
}

/// The two system permissions dictation needs, behind one testable interface.
protocol DictationPermissionsProviding: Sendable {
    func microphoneStatus() -> PermissionStatus
    func speechStatus() -> PermissionStatus

    @discardableResult func requestMicrophone() async -> PermissionStatus
    @discardableResult func requestSpeech() async -> PermissionStatus
}

extension DictationPermissionsProviding {
    /// Requests both permissions in the order the user expects to see them.
    func requestAll() async -> (microphone: PermissionStatus, speech: PermissionStatus) {
        let microphone = await requestMicrophone()
        let speech = await requestSpeech()
        return (microphone, speech)
    }
}

struct SystemDictationPermissions: DictationPermissionsProviding {
    init() {}

    func microphoneStatus() -> PermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    func requestMicrophone() async -> PermissionStatus {
        guard microphoneStatus().canPrompt else { return microphoneStatus() }
        let granted = await AVAudioApplication.requestRecordPermission()
        return granted ? .granted : .denied
    }

    func speechStatus() -> PermissionStatus {
        Self.map(SFSpeechRecognizer.authorizationStatus())
    }

    func requestSpeech() async -> PermissionStatus {
        guard speechStatus().canPrompt else { return speechStatus() }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return Self.map(status)
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}
