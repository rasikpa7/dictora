#if os(macOS)
import SwiftUI

/// Contents of Dictora's menu bar item.
///
/// Intentionally minimal for Phase 1 — the interesting menu bar behaviour
/// (dictate from anywhere, insert into the focused app) arrives with the global
/// shortcut in Phase 2.
struct MenuBarContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MacPlatformServices.self) private var platform

    private var dictation: DictationManager { environment.dictation }

    var body: some View {
        Text("Dictora — \(dictation.state.statusText)")

        Divider()

        Button(dictation.state.isCapturing ? "Stop Dictation" : "Start Dictation") {
            Task { await dictation.toggle() }
        }
        .disabled(!dictation.state.canStart && !dictation.state.isCapturing)
        .keyboardShortcut("d", modifiers: [.command, .shift])

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

        if let result = dictation.result {
            Button("Copy Last Result") {
                Clipboard.copy(result.polishedText)
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
}
#endif
