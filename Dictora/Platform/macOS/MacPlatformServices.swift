#if os(macOS)
import Foundation
import Observation

/// Aggregates the macOS-only capabilities and injects them as one environment value.
///
/// Deliberately *not* part of `AppEnvironment`: the shared environment must stay
/// compilable on iOS, and nothing in `Core` or `Features` may depend on these
/// services. Only `App/macOS` and `Platform/macOS` see this type.
///
/// This is a container of capabilities, not behaviour — the flow that combines
/// them lives in ``SystemDictationCoordinator``.
@MainActor
@Observable
final class MacPlatformServices {
    let accessibility: AccessibilityManager
    let activeApplication: ActiveApplicationManager
    let hotkey: GlobalHotkeyManager
    let menuBar: MenuBarManager
    let overlay: DictationOverlayController
    let textInsertion: TextInsertionManager

    init() {
        let accessibility = AccessibilityManager()
        self.accessibility = accessibility
        self.activeApplication = ActiveApplicationManager()
        self.hotkey = GlobalHotkeyManager()
        self.menuBar = MenuBarManager()
        self.overlay = DictationOverlayController()
        self.textInsertion = TextInsertionManager(accessibility: accessibility)
    }
}
#endif
