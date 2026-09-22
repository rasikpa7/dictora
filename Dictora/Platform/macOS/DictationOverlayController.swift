#if os(macOS)
import AppKit
import Foundation
import SwiftUI

/// Hosts ``DictationOverlayView`` in a borderless floating panel.
///
/// An `NSPanel` with `.nonactivatingPanel` is used instead of a SwiftUI `Window`
/// so showing the overlay never steals focus — the app the user is typing in
/// must stay frontmost for text insertion to reach the right field.
@MainActor
final class DictationOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<DictationOverlayView>?
    private var currentPresentation: OverlayPresentation?

    private(set) var isVisible = false

    init() {}

    func show(_ presentation: OverlayPresentation) {
        guard presentation != currentPresentation || !isVisible else { return }
        currentPresentation = presentation

        let panel = panel ?? makePanel()
        self.panel = panel

        // The hosting view is reused so SwiftUI animates between states instead
        // of the panel flickering on every transcript update.
        if let hostingView {
            hostingView.rootView = DictationOverlayView(presentation: presentation)
        } else {
            let view = NSHostingView(rootView: DictationOverlayView(presentation: presentation))
            hostingView = view
            panel.contentView = view
        }

        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 280, height: 56))
        positionNearBottomOfActiveScreen(panel)

        if !isVisible {
            panel.orderFrontRegardless()
            isVisible = true
        }
    }

    func hide() {
        guard isVisible else { return }
        panel?.orderOut(nil)
        currentPresentation = nil
        isVisible = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 56),
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
        // Follows the pointer's screen rather than the main screen, so the
        // overlay appears where the user is working on a multi-display setup.
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 96)
        )
    }
}
#endif
