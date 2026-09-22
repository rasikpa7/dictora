import SwiftUI

/// Drives the first-run sequence and commits the result to preferences.
///
/// Choices are written straight into `appState.preferences` as the user makes
/// them, but `hasCompletedOnboarding` is only set on the final screen, so
/// quitting midway starts the flow over rather than leaving a half-set-up app.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var step: OnboardingStep = .welcome

    var body: some View {
        @Bindable var appState = environment.appState

        VStack(spacing: 0) {
            if step.showsProgress {
                OnboardingProgress(step: step)
                    .padding(.top, 16)
            }

            Group {
                switch step {
                case .welcome:
                    WelcomeView(onContinue: advance)

                case .microphone:
                    MicrophonePermissionView(
                        microphoneStatus: environment.dictation.microphonePermission,
                        speechStatus: environment.dictation.speechPermission,
                        onRequestAccess: { await environment.dictation.requestPermissions() },
                        onContinue: advance,
                        onBack: goBack
                    )

                case .writingStyle:
                    WritingStyleSetupView(
                        selection: $appState.preferences.selectedWritingStyle,
                        onContinue: advance,
                        onBack: goBack
                    )

                case .customInstructions:
                    CustomInstructionsView(
                        style: appState.preferences.selectedWritingStyle,
                        customInstructions: $appState.preferences.customInstructions,
                        additionalInstructions: $appState.preferences.additionalInstructions,
                        onContinue: advance,
                        onBack: goBack
                    )

                case .complete:
                    SetupCompleteView(selectedStyle: appState.preferences.selectedWritingStyle) {
                        environment.appState.completeOnboarding()
                    }
                }
            }
            .transition(.opacity)
        }
        .animation(.smooth(duration: 0.25), value: step)
        .task { environment.dictation.refreshPermissionStatuses() }
    }

    private func advance() {
        guard let next = step.next else { return }
        step = next
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        step = previous
    }
}

private struct OnboardingProgress: View {
    let step: OnboardingStep

    private var steps: [OnboardingStep] { OnboardingStep.allCases.filter(\.showsProgress) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(steps) { candidate in
                Capsule()
                    .fill(candidate.rawValue <= step.rawValue ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                    .frame(width: candidate == step ? 22 : 8, height: 6)
            }
        }
        .animation(.smooth(duration: 0.25), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue) of \(steps.count)")
    }
}

#Preview {
    OnboardingView()
        .environment(AppEnvironment.preview(preferences: UserPreferences()))
        .frame(width: 520, height: 720)
}
