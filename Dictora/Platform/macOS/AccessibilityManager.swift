#if os(macOS)
import ApplicationServices
import AppKit
import Foundation
import Observation

/// Tracks whether the user has granted Dictora Accessibility access.
///
/// Accessibility is only needed for the Phase 2 capability of typing into
/// another application's focused field. Nothing here reads screen contents —
/// the manager purely reports and requests permission state.
@MainActor
@Observable
final class AccessibilityManager {
    enum Access: Equatable, Sendable {
        case granted
        case notGranted

        var isGranted: Bool { self == .granted }
    }

    private(set) var access: Access = .notGranted

    init() {
        refresh()
    }

    /// Cheap, prompt-free check. Safe to call often.
    @discardableResult
    func refresh() -> Access {
        access = AXIsProcessTrusted() ? .granted : .notGranted
        return access
    }

    /// Shows the system's "allow Accessibility access" prompt.
    ///
    /// The prompt is asynchronous and the user must act in System Settings, so
    /// the returned value reflects the state *before* they respond; callers
    /// should observe `access` afterwards rather than trusting the result.
    @discardableResult
    func requestAccess() -> Access {
        // The literal is used in place of `kAXTrustedCheckOptionPrompt`, which
        // is imported as a mutable global and therefore not concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        access = AXIsProcessTrustedWithOptions(options) ? .granted : .notGranted
        return access
    }

    /// Deep-links to the Accessibility pane, for when the prompt has already
    /// been dismissed once and will not reappear.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
