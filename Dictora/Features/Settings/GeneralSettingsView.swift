import SwiftUI

struct GeneralSettingsView: View {
    @Binding var preferences: UserPreferences

    var body: some View {
        Form {
            Section {
                Toggle("Play sounds", isOn: $preferences.playSounds)
                Text("A short cue plays when dictation starts and stops.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Feedback")
            }

            #if os(macOS)
            Section {
                Toggle("Show floating indicator", isOn: $preferences.showFloatingIndicator)
                Text("Displays a small listening overlay while you dictate. Arrives with the global shortcut.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Launch Dictora at login", isOn: $preferences.launchAtLogin)
                Text("Saved now; registering the login item is not implemented yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Mac")
            }
            #endif
        }
        .formStyle(.grouped)
    }
}

#Preview {
    @Previewable @State var preferences = UserPreferences()
    GeneralSettingsView(preferences: $preferences)
        .frame(width: 480, height: 400)
}
