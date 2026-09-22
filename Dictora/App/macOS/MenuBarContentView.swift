#if os(macOS)
import SwiftUI

/// Contents of Dictora's menu bar item.
struct MenuBarContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MacPlatformServices.self) private var platform
    @Environment(SystemDictationCoordinator.self) private var coordinator

    private var dictation: DictationManager { environment.dictation }

    var body: some View {
        Text("Dictora — \(dictation.state.statusText)")

        Divider()

        // Routed through the coordinator so the result is delivered back to the
        // app the user was in before they opened this menu.
        Button(dictation.state.isCapturing ? "Stop Dictation" : "Start Dictation") {
            coordinator.toggleFromMenuBar()
        }
        .disabled(!dictation.state.canStart && !dictation.state.isCapturing)

        if environment.appState.preferences.globalShortcutEnabled,
           platform.hotkey.state.isActive {
            Text("Anywhere: \(HotkeyShortcut.optionSpace.displayString)")
        }

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
