#if os(macOS)
import SwiftUI

/// macOS-only settings for dictating from anywhere on the Mac.
///
/// Takes plain values and closures rather than the platform services, so this
/// stays a `Features` view with no dependency on `Platform/macOS`.
struct ShortcutSettingsView: View {
    @Binding var preferences: UserPreferences

    /// What is actually listening, which can differ from the chosen preset when
    /// the choice could not be registered.
    let activePreset: ShortcutPreset?
    let fallbackReason: String?
    let registrationFailure: String?
    let isAccessibilityGranted: Bool
    let isInputMonitoringGranted: Bool
    let onRequestInputMonitoring: () -> Void
    let onRequestAccessibility: () -> Void
    let onRepairAccessibility: () -> Void
    let onOpenAccessibilitySettings: () -> Void

    private var chosen: ShortcutPreset { preferences.shortcutPreset }

    var body: some View {
        Form {
            Section {
                Toggle("Dictate from anywhere", isOn: $preferences.globalShortcutEnabled)

                Picker("Shortcut", selection: $preferences.shortcutPreset) {
                    ForEach(ShortcutPreset.allCases) { preset in
                        Text("\(preset.displayName)  ·  \(preset.displayString)").tag(preset)
                    }
                }
                .disabled(!preferences.globalShortcutEnabled)

                Text(chosen.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if preferences.globalShortcutEnabled {
                    statusRow
                }

                if preferences.globalShortcutEnabled, chosen == .fnGlobe, !isInputMonitoringGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("The Fn key needs Input Monitoring access", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("macOS treats watching a lone key as input monitoring. Until it's allowed, Dictora listens on a chord shortcut instead.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Allow Input Monitoring…", action: onRequestInputMonitoring)
                            .buttonStyle(.borderedProminent)
                    }
                }
            } header: {
                Text("Global shortcut")
            }

            Section {
                Picker("Activation", selection: $preferences.hotkeyActivationMode) {
                    ForEach(HotkeyActivationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .disabled(!preferences.globalShortcutEnabled)

                Text(preferences.hotkeyActivationMode.shortDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How it starts")
            }

            Section {
                Toggle("Insert text into the focused field", isOn: $preferences.insertTextAutomatically)
                Text(preferences.insertTextAutomatically
                    ? "When you finish speaking, Dictora types the polished text into the field you were using."
                    : "Dictora copies the polished text to your clipboard instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                AccessibilityStatusRow(
                    isGranted: isAccessibilityGranted,
                    onRequest: onRequestAccessibility,
                    onRepair: onRepairAccessibility,
                    onOpenSettings: onOpenAccessibilitySettings
                )
            } header: {
                Text("Delivering the result")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusRow: some View {
        if let activePreset, activePreset != chosen {
            Label(
                "\(chosen.displayString) isn't available, so \(activePreset.displayString) is listening instead.\(fallbackReason.map { " \($0)" } ?? "")",
                systemImage: "arrow.turn.down.right"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
        } else if activePreset != nil {
            Label("\(chosen.displayString) is registered and listening.", systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.green)
        } else {
            Label(
                registrationFailure ?? "No shortcut is listening yet.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
        }
    }
}

private struct AccessibilityStatusRow: View {
    let isGranted: Bool
    let onRequest: () -> Void
    let onRepair: () -> Void
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
                Text("Without it, Dictora can't watch for the Fn key or type into other apps, and results land on your clipboard instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("If System Settings already shows Dictora switched on, the entry is stale — it was approved for an earlier build. Repair removes it so you can grant it again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Grant Access…", action: onRequest)
                        .buttonStyle(.borderedProminent)
                    Button("Repair", action: onRepair)
                    Button("Open System Settings", action: onOpenSettings)
                }
            }
        }
    }
}

#Preview("Fell back to a chord") {
    @Previewable @State var preferences = UserPreferences()
    ShortcutSettingsView(
        preferences: $preferences,
        activePreset: .optionSpace,
        fallbackReason: "Dictora needs Accessibility access to watch for the Fn key.",
        registrationFailure: nil,
        isAccessibilityGranted: false,
        isInputMonitoringGranted: false,
        onRequestInputMonitoring: {},
        onRequestAccessibility: {},
        onRepairAccessibility: {},
        onOpenAccessibilitySettings: {}
    )
    .frame(width: 580, height: 680)
}
#endif
