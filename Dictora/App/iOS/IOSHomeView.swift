#if os(iOS)
import SwiftUI

/// The iOS home screen: dictation plus a way into settings.
///
/// The dictation surface itself is the shared ``DictationView``; this file adds
/// only the iOS navigation chrome.
struct IOSHomeView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            DictationView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            environment.appState.isPresentingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
        }
    }
}

#Preview {
    IOSHomeView()
        .environment(AppEnvironment.preview())
}
#endif
