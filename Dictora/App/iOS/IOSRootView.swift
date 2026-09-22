#if os(iOS)
import SwiftUI

/// Chooses between first-run onboarding and the home screen.
struct IOSRootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var appState = environment.appState

        Group {
            if appState.hasCompletedOnboarding {
                IOSHomeView()
            } else {
                OnboardingView()
            }
        }
        .animation(.smooth(duration: 0.3), value: appState.hasCompletedOnboarding)
        .sheet(isPresented: $appState.isPresentingSettings) {
            SettingsView { appState.isPresentingSettings = false }
        }
    }
}

#Preview("Onboarding") {
    IOSRootView()
        .environment(AppEnvironment.preview(preferences: UserPreferences()))
}

#Preview("Home") {
    IOSRootView()
        .environment(AppEnvironment.preview())
}
#endif
