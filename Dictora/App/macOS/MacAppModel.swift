#if os(macOS)
import Foundation
import Observation

/// Owns the macOS object graph for the lifetime of the process.
///
/// The dictate-anywhere flow must keep working when the main window is closed,
/// so the coordinator is held here — by the `App` — rather than by any view.
@MainActor
@Observable
final class MacAppModel {
    let environment: AppEnvironment
    let platform: MacPlatformServices
    let coordinator: SystemDictationCoordinator

    private var hasStarted = false

    init() {
        let environment = AppEnvironment.live()
        let platform = MacPlatformServices()

        self.environment = environment
        self.platform = platform
        self.coordinator = SystemDictationCoordinator(environment: environment, platform: platform)
    }

    /// Called from the window's `.task`, which re-runs whenever the window is
    /// reopened; both the environment bootstrap and the coordinator are idempotent.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        await environment.bootstrap()
        coordinator.start()
    }
}
#endif
