import Foundation

/// The first-run sequence, in order.
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case microphone
    case writingStyle
    case customInstructions
    case complete

    var id: Int { rawValue }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// The welcome screen shows no progress dots; the rest do.
    var showsProgress: Bool { self != .welcome }
}
