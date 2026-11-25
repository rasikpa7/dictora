import AVFoundation
import Foundation

/// Short audio cues marking the start, stop and completion of dictation.
///
/// Prefers bundled Dictora sounds over system alerts so the feedback feels
/// deliberate and consistent across platforms.
@MainActor
final class SoundFeedback {
    enum Cue: Sendable {
        case start
        case stop
        case complete

        fileprivate var resourceName: String {
            switch self {
            case .start: "dictora-start"
            case .stop: "dictora-stop"
            case .complete: "dictora-complete"
            }
        }
    }

    private var player: AVAudioPlayer?

    init() {}

    func play(_ cue: Cue) {
        guard let url = Bundle.main.url(forResource: cue.resourceName, withExtension: "wav") else {
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.85
            player.prepareToPlay()
            self.player = player
            player.play()
        } catch {
            // Silent failure — sound is feedback, not a hard requirement.
        }
    }
}
