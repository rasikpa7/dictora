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

    /// Whether the text ended up in the user's document without further action.
    var reachedTargetApp: Bool {
        switch self {
        case .insertedViaAccessibility, .pastedViaClipboard: true
        case .copiedToClipboard, .failed: false
        }
    }

    /// Short line for the floating overlay.
    var summary: String {
        switch self {
        case .insertedViaAccessibility, .pastedViaClipboard: "Inserted"
        case .copiedToClipboard: "Copied to clipboard"
        case .failed: "Couldn't insert"
        }
    }

    var detail: String? {
        switch self {
        case .insertedViaAccessibility, .pastedViaClipboard: nil
        case .copiedToClipboard(let reason): reason
        case .failed(let reason): reason
        }
    }
}

/// Delivers polished text into whichever application the user was typing in.
protocol TextInserting: Sendable {
    @MainActor
    func insert(_ text: String, into targetProcessID: pid_t?) async -> TextInsertionOutcome
}

/// Accessibility-first insertion with a clipboard fallback.
///
/// Strategy order is deliberate: writing through the Accessibility API leaves
/// the user's clipboard untouched, so it is tried first. Synthetic ⌘V is the
/// fallback for apps that don't expose an editable AX element (many Electron
/// and web views). No app-specific special-casing is performed.
@MainActor
struct TextInsertionManager: TextInserting {
    private let accessibility: AccessibilityManager
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "TextInsertion")

    /// Time for the receiving app to read the pasteboard before it is restored.
    private static let pasteSettleDelay = Duration.milliseconds(250)

    init(accessibility: AccessibilityManager) {
        self.accessibility = accessibility
    }

    /// - Parameter targetProcessID: The app the user dictated from. When given,
    ///   the focused element is looked up inside that process rather than
    ///   system-wide, which avoids writing into the wrong window if focus moved.
    func insert(_ text: String, into targetProcessID: pid_t? = nil) async -> TextInsertionOutcome {
        guard !text.isEmpty else { return .failed(reason: "There was nothing to insert.") }

        guard accessibility.refresh().isGranted else {
            Clipboard.copy(text)
            return .copiedToClipboard(
                reason: "Grant Dictora Accessibility access to type directly into other apps. The text is on your clipboard."
            )
        }

        if insertUsingAccessibility(text, targetProcessID: targetProcessID) {
            return .insertedViaAccessibility
        }

        return await pasteUsingClipboard(text)
    }

    // MARK: - Strategy 1: Accessibility

    private func insertUsingAccessibility(_ text: String, targetProcessID: pid_t?) -> Bool {
        let root = targetProcessID.map(AXUIElementCreateApplication) ?? AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            root,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusStatus == .success, let focusedValue = focused else { return false }

        // Safe because kAXFocusedUIElementAttribute is documented to return an
        // AXUIElement; the CFGetTypeID check keeps that assumption honest.
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return false }
        let element = unsafeDowncast(focusedValue, to: AXUIElement.self)

        guard isEditable(element) else { return false }

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

    /// Writing to a read-only element silently succeeds in some apps, so the
    /// element is asked whether the attribute is settable before it is used.
    private func isEditable(_ element: AXUIElement) -> Bool {
        var isSettable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        )
        return status == .success && isSettable.boolValue
    }

    // MARK: - Strategy 2: Clipboard + synthetic paste

    private func pasteUsingClipboard(_ text: String) async -> TextInsertionOutcome {
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

        // The synthetic paste is delivered asynchronously; restoring the
        // clipboard immediately would race the receiving app's read of it.
        if let previousContents {
            try? await Task.sleep(for: Self.pasteSettleDelay)
            Clipboard.copy(previousContents)
        }

        return .pastedViaClipboard
    }
}
#endif
