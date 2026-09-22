#if os(macOS)
import SwiftUI

@main
struct DictoraMacApp: App {
    @State private var model = MacAppModel()

    var body: some Scene {
        Window("Dictora", id: DictoraWindow.main) {
            MacRootView()
                .dictoraEnvironment(model)
                .frame(minWidth: 520, minHeight: 600)
                .task { await model.start() }
        }
        .defaultSize(width: 560, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            MacSettingsView()
                .dictoraEnvironment(model)
        }

        MenuBarExtra {
            MenuBarContentView()
                .dictoraEnvironment(model)
        } label: {
            Image(systemName: model.platform.menuBar.symbolName(for: model.environment.dictation.state))
                .accessibilityLabel(
                    model.platform.menuBar.accessibilityLabel(for: model.environment.dictation.state)
                )
        }
    }
}

extension View {
    /// Injects the three objects every macOS scene needs, so scenes don't repeat
    /// the same chain of `.environment` calls.
    func dictoraEnvironment(_ model: MacAppModel) -> some View {
        environment(model.environment)
            .environment(model.platform)
            .environment(model.coordinator)
    }
}

enum DictoraWindow {
    static let main = "dictora.main"
}
#endif
