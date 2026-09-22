#if os(macOS)
import SwiftUI

/// The macOS main window after onboarding.
///
/// Branding, the shared dictation surface for dictating inside Dictora, and a
/// status strip describing the dictate-anywhere capability — including what is
/// still missing, with the action needed to fix it.
struct MacWelcomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MacPlatformServices.self) private var platform
    @Environment(SystemDictationCoordinator.self) private var coordinator
    @Environment(\.openSettings) private var openSettings

    private var preferences: UserPreferences { environment.appState.preferences }
    private var needsAccessibility: Bool {
        preferences.globalShortcutEnabled
            && preferences.insertTextAutomatically
            && !platform.accessibility.access.isGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if needsAccessibility {
                AccessibilityPrompt(
                    onGrant: { platform.accessibility.requestAccess() },
                    onOpenSettings: { platform.accessibility.openSystemSettings() }
                )
            }

            DictationView(showsHeader: false)

            Divider()

            statusBar
        }
        .background(.background)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "waveform")
                .font(.title)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Dictora")
                    .font(.title2.weight(.semibold))
                Label(
                    environment.appState.currentWritingStyle.displayName,
                    systemImage: environment.appState.currentWritingStyle.symbolName
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Settings…", systemImage: "gearshape") { openSettings() }
                .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapabilityRow(
                symbolName: "keyboard",
                title: "Dictate anywhere",
                detail: shortcutDetail
            )
            CapabilityRow(
                symbolName: "text.cursor",
                title: "Insert into other apps",
                detail: insertionDetail
            )
            CapabilityRow(
                symbolName: "sparkles",
                title: "Rewriting",
                detail: environment.textProcessing.primaryAvailability.explanation
                    ?? "Using \(environment.textProcessing.activeProcessorKind.displayName) on this Mac."
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
    }

    private var shortcutDetail: String {
        guard preferences.globalShortcutEnabled else {
            return "Turned off in Settings › Anywhere."
        }
        if case .failed(let reason) = platform.hotkey.state { return reason }
        guard platform.hotkey.state.isActive else { return "Not registered yet." }

        let shortcut = HotkeyShortcut.optionSpace.displayString
        return preferences.hotkeyActivationMode == .holdToTalk
            ? "Hold \(shortcut) anywhere on your Mac and speak."
            : "Press \(shortcut) anywhere on your Mac to start and stop."
    }

    private var insertionDetail: String {
        guard preferences.insertTextAutomatically else {
            return "Turned off — results are copied to your clipboard instead."
        }
        guard platform.accessibility.access.isGranted else {
            return "Needs Accessibility access. Until then, results go to your clipboard."
        }
        if let outcome = coordinator.lastInsertion {
            return outcome.detail ?? "Last result: \(outcome.summary.lowercased())."
        }
        return "Ready. Polished text is typed into whichever app you were using."
    }
}

/// Shown only while the feature the user has enabled cannot actually work.
private struct AccessibilityPrompt: View {
    let onGrant: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.open")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("One more step to dictate anywhere")
                    .font(.subheadline.weight(.semibold))
                Text("Dictora needs Accessibility access to type into other apps. Without it, dictation still works — the result just lands on your clipboard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Grant Access…", action: onGrant)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Open System Settings", action: onOpenSettings)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .accessibilityElement(children: .contain)
    }
}

private struct CapabilityRow: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbolName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 130, alignment: .leading)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let model = MacAppModel()
    MacWelcomeView()
        .dictoraEnvironment(model)
        .frame(width: 560, height: 700)
}
#endif
