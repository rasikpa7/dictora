#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The one place that knows which pasteboard API this platform uses.
///
/// macOS also relies on this for the Phase 2 clipboard-paste fallback in
/// `TextInsertionManager`, which is why it lives in Core rather than in a view.
enum Clipboard {
    @MainActor
    static func copy(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    @MainActor
    static func currentString() -> String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        UIPasteboard.general.string
        #endif
    }
}
