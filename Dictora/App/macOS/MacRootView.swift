#if os(macOS)
import SwiftUI

/// Root of the macOS main window.
///
/// Also the single place where macOS-only side effects are attached to shared
/// state: registering the global shortcut and mirroring dictation state onto
/// the floating overlay.
struct MacRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(MacPlatformServices.self) private var platform

    var body: some View {
        Group {
            if environment.appState.hasCompletedOnboarding {
                MacWelcomeView()
            } else {
                OnboardingView()
            }
        }
        .animation(.smooth(duration: 0.3), value: environment.appState.hasCompletedOnboarding)
        .task {
            platform.bootstrap {
                Task { await environment.dictation.toggle() }
            }
        }
        .onChange(of: environment.dictation.state) { _, state in
            platform.syncOverlay(
                with: state,
                transcriptPreview: environment.dictation.transcript.displayText,
                isEnabled: environment.appState.preferences.showFloatingIndicator
            )
        }
    }
}

#Preview {
    MacRootView()
        .environment(AppEnvironment.preview())
        .environment(MacPlatformServices())
        .frame(width: 560, height: 700)
}
#endif
