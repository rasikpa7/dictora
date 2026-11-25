#if os(macOS)
import AppKit
import Foundation
import SwiftUI

/// Hosts ``DictationOverlayView`` in a borderless floating panel.
///
/// An `NSPanel` with `.nonactivatingPanel` is used instead of a SwiftUI `Window`
/// so showing the overlay never steals focus — the app the user is typing in
/// must stay frontmost for text insertion to reach the right field.
///
/// The panel has a fixed size and never resizes: the content morphs inside it.
/// That keeps updates (the voice meter alone changes ~30 times a second) cheap
/// and lets SwiftUI animate between states.
@MainActor
final class DictationOverlayController {
    private static let panelSize = NSSize(width: 440, height: 190)
    private static let fadeIn = 0.16
    private static let fadeOut = 0.22

    private var panel: NSPanel?
    private let model = OverlayModel(presentation: OverlayPresentation(state: .idle))
    private var currentPresentation: OverlayPresentation?
    /// Distinguishes the latest hide request, so a show that arrives during a
    /// fade-out is not undone when the fade finishes.
    private var hideGeneration = 0

    private(set) var isVisible = false

    init() {}

    func show(_ presentation: OverlayPresentation) {
        guard presentation != currentPresentation || !isVisible else { return }
        currentPresentation = presentation
        model.presentation = presentation
        hideGeneration += 1

        let panel = panel ?? makePanel()
        self.panel = panel

        if !isVisible {
            positionNearBottomOfActiveScreen(panel)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            isVisible = true
            animate(panel, alpha: 1, duration: Self.fadeIn)
            slideIntoPlace(panel)
        } else if panel.alphaValue < 1 {
            // Reappearing during a fade-out.
            animate(panel, alpha: 1, duration: Self.fadeIn)
        }
    }

    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        currentPresentation = nil
        hideGeneration += 1
        let generation = hideGeneration

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOut
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation, !self.isVisible else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func animate(_ panel: NSPanel, alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }

    /// A short rise from just below the resting position.
    private func slideIntoPlace(_ panel: NSPanel) {
        let resting = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: resting.x, y: resting.y - 14))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            panel.animator().setFrameOrigin(resting)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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

        let hosting = NSHostingView(rootView: DictationOverlayView(model: model))
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = hosting
        return panel
    }

    /// Follows the pointer's screen rather than the main screen, so the overlay
    /// appears where the user is working on a multi-display setup.
    private func positionNearBottomOfActiveScreen(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 56))
    }
}
#endif
