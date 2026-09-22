#if os(macOS)
import SwiftUI

/// The macOS main window after onboarding.
///
/// Phase 1 keeps this simple: branding, the shared dictation surface for
/// testing inside the app, and an honest status panel describing which
/// system-wide capabilities are still to come.
struct MacWelcomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MacPlatformServices.self) private var platform
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

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
                title: "Global shortcut",
                detail: platform.hotkey.state.isActive
                    ? "\(HotkeyShortcut.optionSpace.displayString) is registered. Triggering dictation from other apps arrives in Phase 2."
                    : hotkeyDetail
            )
            CapabilityRow(
                symbolName: "text.cursor",
                title: "Insert into other apps",
                detail: platform.accessibility.access.isGranted
                    ? "Accessibility access granted. Insertion lands in Phase 2."
                    : "Needs Accessibility access, and the App Sandbox must be turned off. Not enabled yet."
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

    private var hotkeyDetail: String {
        if case .failed(let reason) = platform.hotkey.state { return reason }
        return "Not registered yet."
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
    MacWelcomeView()
        .environment(AppEnvironment.preview())
        .environment(MacPlatformServices())
        .frame(width: 560, height: 700)
}
#endif
