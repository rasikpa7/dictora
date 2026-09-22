import AudioToolbox
import Foundation

/// Short system sounds marking the start and end of dictation.
///
/// Uses `AudioToolbox` system sound IDs rather than bundled audio files so the
/// initial project ships no binary assets; swap in custom sounds later by
/// changing only this type.
struct SoundFeedback: Sendable {
    enum Cue: Sendable {
        case start
        case stop
        case complete
    }

    init() {}

    func play(_ cue: Cue) {
        AudioServicesPlaySystemSound(Self.systemSoundID(for: cue))
    }

    private static func systemSoundID(for cue: Cue) -> SystemSoundID {
        #if os(iOS)
        switch cue {
        case .start: 1113   // begin_record
        case .stop: 1114    // end_record
        case .complete: 1057
        }
        #else
        // macOS has no dedicated recording cues; the generic UI sound is the
        // least intrusive option available without bundling audio.
        switch cue {
        case .start, .stop, .complete: kSystemSoundID_UserPreferredAlert
        }
        #endif
    }
}
