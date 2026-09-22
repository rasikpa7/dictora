import SwiftUI

/// Shared settings surface.
///
/// The sections are identical on both platforms; only the container differs —
/// a tabbed preferences window on macOS, a pushed list on iOS.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Provided on iOS, where settings are presented modally.
    var onDone: (() -> Void)?

    var body: some View {
        @Bindable var appState = environment.appState

        #if os(macOS)
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(preferences: $appState.preferences)
            }
            Tab("Writing", systemImage: "text.badge.checkmark") {
                WritingSettingsView(preferences: $appState.preferences)
            }
            Tab("Privacy", systemImage: "hand.raised") {
                privacy
            }
        }
        .frame(width: 560, height: 560)
        .task { await environment.textProcessing.refreshAvailability() }
        #else
        NavigationStack {
            List {
                NavigationLink {
                    GeneralSettingsView(preferences: $appState.preferences)
                        .navigationTitle("General")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("General", systemImage: "gearshape")
                }

                NavigationLink {
                    WritingSettingsView(preferences: $appState.preferences)
                        .navigationTitle("Writing")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Writing", systemImage: "text.badge.checkmark")
                }

                NavigationLink {
                    privacy
                        .navigationTitle("Privacy")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Privacy", systemImage: "hand.raised")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                if let onDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
            }
        }
        .task { await environment.textProcessing.refreshAvailability() }
        #endif
    }

    private var privacy: some View {
        PrivacySettingsView(
            processorAvailability: environment.textProcessing.primaryAvailability,
            activeProcessor: environment.textProcessing.activeProcessorKind,
            microphoneStatus: environment.dictation.microphonePermission,
            speechStatus: environment.dictation.speechPermission
        )
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment.preview())
}
