#if os(macOS)
import SwiftUI

/// macOS-only settings for dictating from anywhere on the Mac.
///
/// Takes plain values and closures rather than the platform services, so this
/// stays a `Features` view with no dependency on `Platform/macOS`.
struct ShortcutSettingsView: View {
    @Binding var preferences: UserPreferences

    let shortcutDisplayString: String
    let isShortcutRegistered: Bool
    let shortcutFailureReason: String?
    let isAccessibilityGranted: Bool
    let onRequestAccessibility: () -> Void
    let onOpenAccessibilitySettings: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Dictate from anywhere", isOn: $preferences.globalShortcutEnabled)

                LabeledContent("Shortcut") {
                    Text(shortcutDisplayString)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }

                if preferences.globalShortcutEnabled {
                    if let shortcutFailureReason {
                        Label(shortcutFailureReason, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else if isShortcutRegistered {
                        Label("Registered and listening.", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Global shortcut")
            } footer: {
                Text("The shortcut is fixed to \(shortcutDisplayString) for now. Customisation is planned.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Activation", selection: $preferences.hotkeyActivationMode) {
                    ForEach(HotkeyActivationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.inline)

                Text(preferences.hotkeyActivationMode.shortDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How it starts")
            }

            Section {
                Toggle("Insert text into the focused field", isOn: $preferences.insertTextAutomatically)
                Text(preferences.insertTextAutomatically
                    ? "Dictora types the polished text into whichever app you were using."
                    : "Dictora copies the polished text to your clipboard instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                AccessibilityStatusRow(
                    isGranted: isAccessibilityGranted,
                    onRequest: onRequestAccessibility,
                    onOpenSettings: onOpenAccessibilitySettings
                )
            } header: {
                Text("Delivering the result")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccessibilityStatusRow: View {
    let isGranted: Bool
    let onRequest: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Accessibility access") {
                if isGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Required", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if !isGranted {
                Text("Without Accessibility access, Dictora can't type into other apps and will leave the text on your clipboard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Grant Access…", action: onRequest)
                        .buttonStyle(.borderedProminent)
                    Button("Open System Settings", action: onOpenSettings)
                }
            }
        }
    }
}

#Preview("Needs access") {
    @Previewable @State var preferences = UserPreferences()
    ShortcutSettingsView(
        preferences: $preferences,
        shortcutDisplayString: "⌥Space",
        isShortcutRegistered: true,
        shortcutFailureReason: nil,
        isAccessibilityGranted: false,
        onRequestAccessibility: {},
        onOpenAccessibilitySettings: {}
    )
    .frame(width: 560, height: 620)
}
#endif
