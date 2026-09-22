import SwiftUI

/// Requests the two permissions dictation needs, and explains what happens if
/// the user has already said no (in which case only System Settings can help).
struct MicrophonePermissionView: View {
    let microphoneStatus: PermissionStatus
    let speechStatus: PermissionStatus
    let onRequestAccess: () async -> Void
    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var isRequesting = false

    private var allGranted: Bool { microphoneStatus.isGranted && speechStatus.isGranted }
    private var isBlocked: Bool { !microphoneStatus.canPrompt && !speechStatus.canPrompt && !allGranted }

    var body: some View {
        OnboardingScaffold(
            symbolName: "mic.circle",
            title: "Enable your microphone",
            message: "Dictora needs microphone access to hear you, and speech recognition to turn what you say into text. Nothing is recorded or stored."
        ) {
            VStack(spacing: 12) {
                PermissionRow(
                    symbolName: "mic",
                    title: "Microphone",
                    detail: "Dictora uses your microphone to turn your voice into text.",
                    status: microphoneStatus
                )
                PermissionRow(
                    symbolName: "waveform.badge.mic",
                    title: "Speech Recognition",
                    detail: "Dictora uses speech recognition to transcribe your dictation.",
                    status: speechStatus
                )

                if isBlocked {
                    Text("Access was declined. Open System Settings › Privacy & Security to grant it, then come back.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        } footer: {
            VStack(spacing: 10) {
                if allGranted {
                    OnboardingPrimaryButton(title: "Continue", action: onContinue)
                } else {
                    OnboardingPrimaryButton(title: "Allow Access", isEnabled: !isRequesting) {
                        Task {
                            isRequesting = true
                            await onRequestAccess()
                            isRequesting = false
                        }
                    }
                    Button("Set Up Later", action: onContinue)
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button("Back", action: onBack)
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct PermissionRow: View {
    let symbolName: String
    let title: String
    let detail: String
    let status: PermissionStatus

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            statusBadge
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dictoraCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Granted")
        case .denied, .restricted:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Not granted")
        case .notDetermined:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Not requested yet")
        }
    }
}

#Preview {
    MicrophonePermissionView(
        microphoneStatus: .granted,
        speechStatus: .notDetermined,
        onRequestAccess: {},
        onContinue: {},
        onBack: {}
    )
    .frame(width: 520, height: 620)
}
