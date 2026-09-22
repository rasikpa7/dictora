#if os(macOS)
import SwiftUI

/// macOS preferences window.
///
/// Lives in `App/macOS` rather than `Features/Settings` because it is the point
/// where shared section views are combined with macOS-only platform services;
/// the section views themselves stay free of any platform dependency.
struct MacSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MacPlatformServices.self) private var platform

    var body: some View {
        @Bindable var appState = environment.appState

        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(preferences: $appState.preferences)
            }
            Tab("Writing", systemImage: "text.badge.checkmark") {
                WritingSettingsView(preferences: $appState.preferences)
            }
            Tab("Anywhere", systemImage: "keyboard") {
                ShortcutSettingsView(
                    preferences: $appState.preferences,
                    shortcutDisplayString: HotkeyShortcut.optionSpace.displayString,
                    isShortcutRegistered: platform.hotkey.state.isActive,
                    shortcutFailureReason: shortcutFailureReason,
                    isAccessibilityGranted: platform.accessibility.access.isGranted,
                    onRequestAccessibility: { platform.accessibility.requestAccess() },
                    onOpenAccessibilitySettings: { platform.accessibility.openSystemSettings() }
                )
            }
            Tab("Privacy", systemImage: "hand.raised") {
                PrivacySettingsView(
                    processorAvailability: environment.textProcessing.primaryAvailability,
                    activeProcessor: environment.textProcessing.activeProcessorKind,
                    microphoneStatus: environment.dictation.microphonePermission,
                    speechStatus: environment.dictation.speechPermission
                )
            }
        }
        .frame(width: 580, height: 600)
        .task {
            await environment.textProcessing.refreshAvailability()
            platform.accessibility.refresh()
        }
    }

    private var shortcutFailureReason: String? {
        if case .failed(let reason) = platform.hotkey.state { return reason }
        return nil
    }
}

#Preview {
    let model = MacAppModel()
    MacSettingsView()
        .dictoraEnvironment(model)
}
#endif
