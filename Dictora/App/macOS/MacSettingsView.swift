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
    @Environment(SystemDictationCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var appState = environment.appState

        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(preferences: $appState.preferences)
            }
            Tab("Writing", systemImage: "text.badge.checkmark") {
                WritingSettingsView(preferences: $appState.preferences)
            }
            Tab("Claude", systemImage: "sparkles") {
                ClaudeSettingsView(
                    preferences: $appState.preferences,
                    status: environment.claudeAccount.status,
                    hasKey: environment.claudeAccount.hasKey,
                    lastIssue: environment.textProcessing.lastCloudIssue,
                    onConnect: { key in Task { await environment.claudeAccount.connect(key: key) } },
                    onTest: { Task { await environment.claudeAccount.testSavedKey() } },
                    onDisconnect: { environment.claudeAccount.disconnect() }
                )
            }
            Tab("Anywhere", systemImage: "keyboard") {
                ShortcutSettingsView(
                    preferences: $appState.preferences,
                    activePreset: coordinator.activePreset,
                    fallbackReason: coordinator.shortcutFallbackReason,
                    registrationFailure: platform.hotkey.state.failureReason,
                    isAccessibilityGranted: platform.accessibility.access.isGranted,
                    isInputMonitoringGranted: platform.accessibility.inputMonitoringGranted,
                    onRequestInputMonitoring: { platform.accessibility.requestInputMonitoring() },
                    onRequestAccessibility: { platform.accessibility.requestAccess() },
                    onRepairAccessibility: { platform.accessibility.resetPermission() },
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
}

#Preview {
    let model = MacAppModel()
    MacSettingsView()
        .dictoraEnvironment(model)
}
#endif
