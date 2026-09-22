#if os(macOS)
import SwiftUI

@main
struct DictoraMacApp: App {
    @State private var environment = AppEnvironment.live()
    @State private var platform = MacPlatformServices()

    var body: some Scene {
        Window("Dictora", id: DictoraWindow.main) {
            MacRootView()
                .environment(environment)
                .environment(platform)
                .frame(minWidth: 520, minHeight: 600)
                .task { await environment.bootstrap() }
        }
        .defaultSize(width: 560, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(environment)
        }

        MenuBarExtra {
            MenuBarContentView()
                .environment(environment)
                .environment(platform)
        } label: {
            Image(systemName: platform.menuBar.symbolName(for: environment.dictation.state))
                .accessibilityLabel(platform.menuBar.accessibilityLabel(for: environment.dictation.state))
        }
    }
}

enum DictoraWindow {
    static let main = "dictora.main"
}
#endif
