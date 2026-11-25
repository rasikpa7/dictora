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

/// Delivers text into the focused field of the app the user was typing in.
///
/// Three strategies, tried in order, each only counting as success when it can
/// be shown to have worked:
///
/// 1. **Accessibility** — write the selection directly, then read the field back.
///    Many apps (browsers, Electron) accept the write and silently ignore it, so
///    a write that doesn't change the field's value is treated as a failure.
/// 2. **Paste** — put the text on the clipboard, send ⌘V, and restore everything
///    that was on the clipboard before, not just plain text.
/// 3. **Clipboard** — leave the text there and say so.
///
/// Nothing is written into the user's document while they are still speaking;
/// the text goes in once, at the end.
@MainActor
final class TextInsertionManager: TextInserting {
    private let accessibility: AccessibilityManager
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "TextInsertion")

    /// Time for the receiving app to read the pasteboard before it is restored.
    private static let pasteSettleDelay = Duration.milliseconds(500)
    /// Time for an app to apply an Accessibility write before it is read back.
    private static let verifyDelay = Duration.milliseconds(60)
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

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

        if await insertUsingAccessibility(text, targetProcessID: targetProcessID) {
            logger.info("Inserted via Accessibility (verified)")
            return .insertedViaAccessibility
        }

        return await pasteUsingClipboard(text)
    }

    // MARK: - Strategy 1: Accessibility, verified

    private func insertUsingAccessibility(_ text: String, targetProcessID: pid_t?) async -> Bool {
        guard let element = focusedElement(in: targetProcessID), isEditable(element) else {
            return false
        }
        // Without a readable value there is no way to confirm the write, and a
        // write that silently worked followed by a paste would duplicate text.
        guard let before = stringValue(of: element) else { return false }

        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        guard status == .success else {
            logger.debug("Accessibility insertion refused (status \(status.rawValue, privacy: .public))")
            return false
        }

        try? await Task.sleep(for: Self.verifyDelay)
        guard let after = stringValue(of: element), after != before else {
            logger.notice("Accessibility write reported success but the field didn't change; using paste")
            return false
        }
        return true
    }

    private func focusedElement(in targetProcessID: pid_t?) -> AXUIElement? {
        let root: AXUIElement
        if let targetProcessID {
            let application = AXUIElementCreateApplication(targetProcessID)
            // Chromium and Electron apps expose their text fields to
            // Accessibility only when asked.
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            root = application
        } else {
            root = AXUIElementCreateSystemWide()
        }

        var focused: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            root,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusStatus == .success, let focusedValue = focused else { return nil }
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(focusedValue, to: AXUIElement.self)
    }

    private func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard status == .success else { return nil }
        return value as? String
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

    func pasteUsingClipboard(_ text: String) async -> TextInsertionOutcome {
        let pasteboard = NSPasteboard.general
        let saved = Self.snapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Tells clipboard managers this is a temporary hand-off, not a copy.
        pasteboard.setData(Data(), forType: Self.transientType)
        let ourChangeCount = pasteboard.changeCount

        // A held modifier (hold-to-talk on ⌥Space, say) would turn ⌘V into
        // ⌥⌘V. Give the user a moment to let go.
        await waitForModifiersToBeReleased()

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return .copiedToClipboard(reason: "Dictora couldn't paste for you, so the text is on your clipboard.")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        logger.info("Pasted via clipboard")

        try? await Task.sleep(for: Self.pasteSettleDelay)
        // Only put the old contents back if nothing else has touched the
        // clipboard meanwhile; otherwise the user's newer copy would be lost.
        if pasteboard.changeCount == ourChangeCount {
            Self.restore(saved, to: pasteboard)
        }
        return .pastedViaClipboard
    }

    private func waitForModifiersToBeReleased() async {
        let held: CGEventFlags = [.maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        for _ in 0..<30 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(held).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Everything on the pasteboard, as raw data per type, so images, files and
    /// rich text survive a paste round-trip.
    private static func snapshot(of pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }
    }

    private static func restore(_ saved: [[(NSPasteboard.PasteboardType, Data)]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }
        let items = saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
#endif
