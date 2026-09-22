#if os(macOS)
import AppKit
import Foundation
import Observation

/// Presentation state and behaviour for Dictora's `MenuBarExtra`.
///
/// Holds only what the SwiftUI menu cannot express itself — icon mapping and
/// AppKit-level window activation — so the menu content view stays declarative.
@MainActor
@Observable
final class MenuBarManager {
    /// Bound to `MenuBarExtra(isInserted:)`-style presentation so dictation
    /// triggered by the global shortcut can close an open menu.
    var isMenuPresented = false

    init() {}

    func symbolName(for state: DictationState) -> String {
        switch state {
        case .idle, .completed: "waveform"
        case .requestingPermission: "waveform.badge.exclamationmark"
        case .listening: "waveform.badge.mic"
        case .transcribing, .processing: "waveform.badge.magnifyingglass"
        case .failed: "waveform.badge.exclamationmark"
        }
    }

    func accessibilityLabel(for state: DictationState) -> String {
        "Dictora — \(state.statusText)"
    }

    /// Brings Dictora's main window forward from a menu item.
    func activateMainWindow() {
        isMenuPresented = false
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first { $0.canBecomeMain && $0.isVisible }?
            .makeKeyAndOrderFront(nil)
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
#endif
