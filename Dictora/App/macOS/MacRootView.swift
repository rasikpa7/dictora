#if os(macOS)
import SwiftUI

/// Root of the macOS main window.
///
/// Side effects that must outlive this window — the global shortcut, the
/// floating overlay, text insertion — belong to `SystemDictationCoordinator`,
/// which the app owns. This view only chooses what to show.
struct MacRootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            if environment.appState.hasCompletedOnboarding {
                MacWelcomeView()
            } else {
                OnboardingView()
            }
        }
        .animation(.smooth(duration: 0.3), value: environment.appState.hasCompletedOnboarding)
    }
}

#Preview {
    let model = MacAppModel()
    MacRootView()
        .dictoraEnvironment(model)
        .frame(width: 560, height: 700)
}
#endif
