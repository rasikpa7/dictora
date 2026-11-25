import SwiftUI

/// Privacy disclosures.
///
/// The wording is deliberately conditional ("whenever supported by your
/// device") because on-device processing depends on Apple Intelligence
/// availability, which Dictora cannot guarantee. The live status below tells
/// the user what is actually happening on their machine.
struct PrivacySettingsView: View {
    let processorAvailability: TextProcessorAvailability
    let activeProcessor: TextProcessorKind
    let microphoneStatus: PermissionStatus
    let speechStatus: PermissionStatus

    var body: some View {
        Form {
            Section {
                Text("Dictora is designed to process your voice and writing locally whenever supported by your device.")
                    .font(.callout)
                Text("Dictora has no analytics or accounts. Speech recognition always uses Apple's on-device Speech framework. Rewriting uses Apple's on-device model when your device supports it, unless you connect your own Claude API key in Settings. In that case only the dictated text (never your audio) is sent to Anthropic to be rewritten.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How Dictora handles your data")
            }

            Section {
                LabeledContent("Rewriting") {
                    Text(activeProcessor.displayName)
                        .foregroundStyle(.secondary)
                }
                if let explanation = processorAvailability.explanation {
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("On this device")
            }

            Section {
                LabeledContent("Microphone") {
                    PermissionBadge(status: microphoneStatus)
                }
                LabeledContent("Speech Recognition") {
                    PermissionBadge(status: speechStatus)
                }
                #if os(macOS)
                LabeledContent("Accessibility") {
                    Text("Required later for inserting text into other apps")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                #endif
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionBadge: View {
    let status: PermissionStatus

    var body: some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .foregroundStyle(.orange)
        case .restricted:
            Label("Restricted", systemImage: "lock.circle.fill")
                .foregroundStyle(.orange)
        case .notDetermined:
            Label("Not requested", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    PrivacySettingsView(
        processorAvailability: .unavailable("Turn on Apple Intelligence to let Dictora rewrite your dictation."),
        activeProcessor: .localFallback,
        microphoneStatus: .granted,
        speechStatus: .notDetermined
    )
    .frame(width: 520, height: 560)
}
