#if os(iOS)
import SwiftUI

/// iOS settings: the shared sections pushed from a list, presented modally.
///
/// macOS uses `MacSettingsView` instead. The container differs because the two
/// platforms present preferences differently; the section views are shared.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var onDone: (() -> Void)?

    var body: some View {
        @Bindable var appState = environment.appState

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
                    PrivacySettingsView(
                        processorAvailability: environment.textProcessing.primaryAvailability,
                        activeProcessor: environment.textProcessing.activeProcessorKind,
                        microphoneStatus: environment.dictation.microphonePermission,
                        speechStatus: environment.dictation.speechPermission
                    )
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
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment.preview())
}
#endif
