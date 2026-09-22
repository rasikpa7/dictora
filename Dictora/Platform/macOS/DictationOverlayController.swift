#if os(macOS)
import AppKit
import Foundation
import SwiftUI

/// Hosts ``DictationOverlayView`` in a borderless floating panel.
///
/// An `NSPanel` with `.nonactivatingPanel` is used instead of a SwiftUI `Window`
/// so showing the overlay never steals focus — the app the user is typing in
/// must stay frontmost for Phase 2 text insertion to target the right field.
@MainActor
final class DictationOverlayController {
    private var panel: NSPanel?
    private(set) var isVisible = false

    init() {}

    func show(state: DictationState, transcriptPreview: String = "") {
        let panel = panel ?? makePanel()
        self.panel = panel

        panel.contentView = NSHostingView(
            rootView: DictationOverlayView(state: state, transcriptPreview: transcriptPreview)
        )
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 260, height: 56))
        positionNearBottomOfActiveScreen(panel)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func update(state: DictationState, transcriptPreview: String = "") {
        guard isVisible else { return }
        show(state: state, transcriptPreview: transcriptPreview)
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    private func positionNearBottomOfActiveScreen(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 96
        )
        panel.setFrameOrigin(origin)
    }
}
#endif
