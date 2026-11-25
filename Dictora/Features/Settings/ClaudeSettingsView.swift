import SwiftUI

/// Connecting Claude for rewriting.
///
/// Takes plain values and closures, so it stays a `Features` view with no
/// dependency on how the key is stored or tested.
struct ClaudeSettingsView: View {
    @Binding var preferences: UserPreferences

    let status: ClaudeAccount.Status
    let hasKey: Bool
    /// Why the last rewrite fell back to the on-device path, if it did.
    let lastIssue: String?
    let onConnect: (String) -> Void
    let onTest: () -> Void
    let onDisconnect: () -> Void

    @State private var keyDraft = ""
    @Environment(\.openURL) private var openURL

    private var isChecking: Bool { status == .checking }

    var body: some View {
        Form {
            Section {
                statusRow

                if hasKey {
                    HStack {
                        Button("Test connection", action: onTest)
                            .disabled(isChecking)
                        Button("Remove key", role: .destructive, action: onDisconnect)
                            .disabled(isChecking)
                    }
                } else {
                    SecureField("sk-ant-…", text: $keyDraft)
                        .textContentType(.password)
                        .disabled(isChecking)
                        .onSubmit(connect)

                    HStack {
                        Button("Connect", action: connect)
                            .buttonStyle(.borderedProminent)
                            .disabled(keyDraft.isEmpty || isChecking)
                        Button("Get an API key") {
                            if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                                openURL(url)
                            }
                        }
                    }
                }

                if case .failed(let message) = status {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Claude")
            } footer: {
                Text("Claude fixes mishearings, understands corrections like “sorry, not that, this”, and cleans up grammar far better than on-device rewriting. Anthropic doesn't allow other apps to sign in with a Claude account, so Dictora uses your own API key. It is stored in your Mac's Keychain.")
            }

            if hasKey {
                Section {
                    Toggle("Use Claude for rewriting", isOn: $preferences.useClaude)

                    Picker("Model", selection: $preferences.claudeModel) {
                        ForEach(ClaudeModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .disabled(!preferences.useClaude)

                    Text(preferences.claudeModel.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let lastIssue {
                        Label("Last rewrite used on-device cleanup instead: \(lastIssue)", systemImage: "arrow.turn.down.right")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Rewriting")
                }
            }

            Section {
                Label(
                    preferences.useClaude && hasKey
                        ? "While Claude is on, the text of what you dictate (not your audio) is sent to Anthropic to be rewritten. Speech recognition still happens on your Mac."
                        : "Nothing leaves your Mac. Speech recognition and rewriting both run on-device.",
                    systemImage: preferences.useClaude && hasKey ? "icloud.and.arrow.up" : "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusRow: some View {
        LabeledContent("Status") {
            switch status {
            case .connected:
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").foregroundStyle(.secondary)
                }
            case .failed:
                Label(hasKey ? "Needs attention" : "Not connected", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            case .notConnected:
                Label("Not connected", systemImage: "circle.dashed").foregroundStyle(.secondary)
            }
        }
    }

    private func connect() {
        guard !keyDraft.isEmpty else { return }
        onConnect(keyDraft)
        keyDraft = ""
    }
}

#Preview("Not connected") {
    @Previewable @State var preferences = UserPreferences()
    ClaudeSettingsView(
        preferences: $preferences, status: .notConnected, hasKey: false, lastIssue: nil,
        onConnect: { _ in }, onTest: {}, onDisconnect: {}
    )
    .frame(width: 540, height: 520)
}

#Preview("Connected") {
    @Previewable @State var preferences = UserPreferences()
    ClaudeSettingsView(
        preferences: $preferences, status: .connected, hasKey: true, lastIssue: nil,
        onConnect: { _ in }, onTest: {}, onDisconnect: {}
    )
    .frame(width: 540, height: 520)
}
