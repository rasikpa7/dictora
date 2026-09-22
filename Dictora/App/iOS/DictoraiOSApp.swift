#if os(iOS)
import SwiftUI

@main
struct DictoraiOSApp: App {
    @State private var environment = AppEnvironment.live()
    @State private var integration = IOSIntegrationService()

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environment(environment)
                .environment(integration)
                .task { await environment.bootstrap() }
        }
    }
}
#endif
