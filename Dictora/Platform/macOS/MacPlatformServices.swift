#if os(macOS)
import Foundation
import Observation
import OSLog

/// Aggregates the macOS-only capabilities and injects them as one environment value.
///
/// Deliberately *not* part of `AppEnvironment`: the shared environment must stay
/// compilable on iOS, and nothing in `Core` or `Features` may depend on these
/// services. Only `App/macOS` and `Platform/macOS` see this type.
@MainActor
@Observable
final class MacPlatformServices {
    let accessibility: AccessibilityManager
    let activeApplication: ActiveApplicationManager
    let hotkey: GlobalHotkeyManager
    let menuBar: MenuBarManager
    let overlay: DictationOverlayController
    let textInsertion: TextInsertionManager

    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "MacPlatform")

    init() {
        let accessibility = AccessibilityManager()
        self.accessibility = accessibility
        self.activeApplication = ActiveApplicationManager()
        self.hotkey = GlobalHotkeyManager()
        self.menuBar = MenuBarManager()
        self.overlay = DictationOverlayController()
        self.textInsertion = TextInsertionManager(accessibility: accessibility)
    }

    /// Starts the always-on macOS behaviour. Called once, from the app's root view.
    func bootstrap(onHotkey: @escaping @MainActor () -> Void) {
        activeApplication.startObserving()
        accessibility.refresh()

        let state = hotkey.register(.optionSpace, onTrigger: onHotkey)
        if case .failed(let reason) = state {
            logger.notice("Global shortcut unavailable: \(reason, privacy: .public)")
        }
    }

    /// Mirrors the dictation state onto the floating overlay.
    func syncOverlay(with state: DictationState, transcriptPreview: String, isEnabled: Bool) {
        guard isEnabled else {
            overlay.hide()
            return
        }

        switch state {
        case .listening, .transcribing, .processing:
            overlay.show(state: state, transcriptPreview: transcriptPreview)
        case .completed, .failed:
            overlay.update(state: state, transcriptPreview: "")
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                overlay.hide()
            }
        case .idle, .requestingPermission:
            overlay.hide()
        }
    }
}
#endif
