#if os(macOS)
import AppKit
import ApplicationServices
import Foundation
import OSLog

/// How a piece of text reached (or failed to reach) the user's focused field.
enum TextInsertionOutcome: Equatable, Sendable {
    /// Written straight into the focused field via the Accessibility API.
    case insertedViaAccessibility
    /// Placed on the clipboard and pasted with a synthetic ⌘V.
    case pastedViaClipboard
    /// Left on the clipboard for the user to paste themselves.
    case copiedToClipboard(reason: String)
    case failed(reason: String)
}

/// Delivers polished text into whichever application the user was typing in.
protocol TextInserting: Sendable {
    @MainActor
    func insert(_ text: String) -> TextInsertionOutcome
}

/// Accessibility-first insertion with a clipboard fallback.
///
/// Strategy order is deliberate: writing through the Accessibility API leaves
/// the user's clipboard untouched, so it is tried first. Synthetic ⌘V is the
/// fallback for apps that don't expose an editable AX element (many Electron
/// and web views). No app-specific special-casing is performed.
///
/// Phase 2 note: this is exercised only once the global shortcut lands. It is
/// written defensively and never traps — the worst case is text left on the
/// clipboard with an explanation.
@MainActor
struct TextInsertionManager: TextInserting {
    private let accessibility: AccessibilityManager
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "TextInsertion")

    init(accessibility: AccessibilityManager) {
        self.accessibility = accessibility
    }

    func insert(_ text: String) -> TextInsertionOutcome {
        guard !text.isEmpty else { return .failed(reason: "There was nothing to insert.") }

        guard accessibility.refresh().isGranted else {
            Clipboard.copy(text)
            return .copiedToClipboard(
                reason: "Grant Dictora Accessibility access to type directly into other apps. The text is on your clipboard."
            )
        }

        if insertUsingAccessibility(text) {
            return .insertedViaAccessibility
        }

        return pasteUsingClipboard(text)
    }

    // MARK: - Strategy 1: Accessibility

    private func insertUsingAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusStatus == .success, let focusedValue = focused else { return false }

        // Safe because kAXFocusedUIElementAttribute is documented to return an
        // AXUIElement; the CFGetTypeID check keeps that assumption honest.
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return false }
        let element = unsafeDowncast(focusedValue, to: AXUIElement.self)

        // Replacing the selection inserts at the caret when nothing is selected,
        // which is what a dictation insert should do.
        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        if status == .success { return true }

        logger.debug("Accessibility insertion unavailable (status \(status.rawValue, privacy: .public))")
        return false
    }

    // MARK: - Strategy 2: Clipboard + synthetic paste

    private func pasteUsingClipboard(_ text: String) -> TextInsertionOutcome {
        let previousContents = Clipboard.currentString()
        Clipboard.copy(text)

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return .copiedToClipboard(reason: "Dictora couldn't paste for you, so the text is on your clipboard.")
        }

        let virtualKeyV: CGKeyCode = 0x09
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
        else {
            return .copiedToClipboard(reason: "Dictora couldn't paste for you, so the text is on your clipboard.")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        restoreClipboard(previousContents)
        return .pastedViaClipboard
    }

    /// Puts the user's own clipboard back after the paste has been delivered.
    private func restoreClipboard(_ previousContents: String?) {
        guard let previousContents else { return }
        Task { @MainActor in
            // The synthetic paste is asynchronous; restoring immediately would
            // race the receiving app's read of the pasteboard.
            try? await Task.sleep(for: .milliseconds(250))
            Clipboard.copy(previousContents)
        }
    }
}
#endif
