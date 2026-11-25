#if os(macOS)
import SwiftUI

/// Contents of Dictora's menu bar item.
struct MenuBarContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MacPlatformServices.self) private var platform
    @Environment(SystemDictationCoordinator.self) private var coordinator

    private var dictation: DictationManager { environment.dictation }

    var body: some View {
        Text("Dictora — \(dictation.speechModel.note ?? dictation.state.statusText)")

        Divider()

        // Routed through the coordinator so the result is delivered back to the
        // app the user was in before they opened this menu.
        Button(dictation.state.isCapturing ? "Stop Dictation" : "Start Dictation") {
            coordinator.toggleFromMenuBar()
        }
        .disabled(!dictation.state.canStart && !dictation.state.isCapturing)

        if environment.appState.preferences.globalShortcutEnabled,
           let active = coordinator.activePreset {
            Text("Anywhere: \(active.displayString)")
        }

        // Each style rephrases the clipboard directly, so the common case —
        // "make this text sound different" — is one menu away from anywhere.
        Menu("Rephrase Clipboard") {
            ForEach(WritingStyle.allCases) { style in
                Button(style.displayName) {
                    coordinator.rephraseClipboard(as: style)
                }
            }
        }
        .disabled(environment.clipboardRewriter.clipboardPreview == nil)

        Menu("Writing Style") {
            ForEach(WritingStyle.allCases) { style in
                Button {
                    environment.appState.selectWritingStyle(style)
                } label: {
                    if style == environment.appState.currentWritingStyle {
                        Label(style.displayName, systemImage: "checkmark")
                    } else {
                        Text(style.displayName)
                    }
                }
            }
        }

        // Everything recently dictated stays one click away, so a result that
        // landed in the wrong place is never lost.
        if !dictation.history.isEmpty {
            Menu("Recent Dictations") {
                ForEach(dictation.history.prefix(10)) { entry in
                    Button(Self.menuTitle(for: entry.polishedText)) {
                        Clipboard.copy(entry.polishedText)
                    }
                }
            }
        }

        Divider()

        Button("Open Dictora") {
            platform.menuBar.activateMainWindow()
        }

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Dictora") {
            platform.menuBar.quit()
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private static func menuTitle(for text: String) -> String {
        let singleLine = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return singleLine.count > 48 ? String(singleLine.prefix(47)) + "…" : singleLine
    }
}
#endif
