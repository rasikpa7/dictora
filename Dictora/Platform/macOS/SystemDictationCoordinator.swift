#if os(macOS)
import AppKit
import Foundation
import Observation
import OSLog

/// Drives "dictate anywhere on the Mac".
///
/// This is the only type that knows the whole Phase 2 flow:
/// global shortcut → remember the app the user was in → dictate → show the
/// floating overlay → insert the polished text back into that app.
///
/// It lives outside any SwiftUI view because the flow must work while Dictora's
/// window is closed, and it owns no capability of its own — every step is
/// delegated to a service on ``MacPlatformServices`` or to ``DictationManager``.
@MainActor
@Observable
final class SystemDictationCoordinator {
    /// Where the current dictation will send its result.
    ///
    /// Dictation started from Dictora's own window stays in Dictora; dictation
    /// started from the shortcut or the menu bar goes back to the app the user
    /// was working in.
    private enum SessionOrigin: Equatable {
        case systemWide
        case inApp
    }

    /// The result of the most recent shortcut-triggered delivery, for the UI.
    private(set) var lastInsertion: TextInsertionOutcome?

    private let environment: AppEnvironment
    private let platform: MacPlatformServices
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "SystemDictation")

    private var origin: SessionOrigin?
    private var targetProcessID: pid_t?
    /// The mode the hotkey was last registered *for*, whether or not that
    /// registration succeeded. Guards against repeated registration attempts.
    private var attemptedShortcutMode: HotkeyActivationMode?
    private var isShortcutRegistered = false

    private var observationTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var overlayDismissTask: Task<Void, Never>?
    private var hasStarted = false

    /// How long a finished overlay stays on screen before fading out.
    private static let overlayLingerDuration = Duration.seconds(1.6)

    init(environment: AppEnvironment, platform: MacPlatformServices) {
        self.environment = environment
        self.platform = platform
    }

    private var dictation: DictationManager { environment.dictation }
    private var preferences: UserPreferences { environment.appState.preferences }

    // MARK: - Lifecycle

    /// Idempotent: the main window's `.task` re-runs whenever it is reopened.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        platform.activeApplication.startObserving()
        platform.accessibility.refresh()
        observeState()
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        platform.hotkey.unregister()
        platform.activeApplication.stopObserving()
        platform.overlay.hide()
        attemptedShortcutMode = nil
        isShortcutRegistered = false
        hasStarted = false
    }

    /// Menu bar "Start Dictation". Behaves like the global shortcut: the result
    /// goes back to the app the user was in before opening the menu.
    func toggleFromMenuBar() {
        if dictation.state.isCapturing {
            finishSession()
        } else {
            beginSession(origin: .systemWide)
        }
    }

    // MARK: - Reconciliation

    /// Everything the coordinator reacts to, gathered in one observable read.
    private struct Snapshot: Equatable, Sendable {
        var state: DictationState
        var transcript: String
        var shortcutEnabled: Bool
        var activationMode: HotkeyActivationMode
        var showsOverlay: Bool
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(
            state: dictation.state,
            transcript: dictation.transcript.displayText,
            shortcutEnabled: preferences.globalShortcutEnabled,
            activationMode: preferences.hotkeyActivationMode,
            showsOverlay: preferences.showFloatingIndicator
        )
    }

    /// Reacts to dictation and preference changes in a single loop.
    ///
    /// `Observations` is used instead of a SwiftUI `onChange` so the overlay and
    /// the shortcut registration stay correct even with no window on screen.
    private func observeState() {
        let updates = Observations { [weak self] in
            self?.currentSnapshot()
        }

        observationTask = Task { [weak self] in
            self?.apply(self?.currentSnapshot())
            for await snapshot in updates {
                guard !Task.isCancelled else { return }
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: Snapshot?) {
        guard let snapshot else { return }
        reconcileShortcut(enabled: snapshot.shortcutEnabled, mode: snapshot.activationMode)
        updateOverlay(for: snapshot)
    }

    private func reconcileShortcut(enabled: Bool, mode: HotkeyActivationMode) {
        guard enabled else {
            if attemptedShortcutMode != nil {
                platform.hotkey.unregister()
                attemptedShortcutMode = nil
                isShortcutRegistered = false
            }
            return
        }
        // Registration is attempted once per activation mode — including when it
        // failed, so a shortcut conflict doesn't retry on every transcript
        // update. Toggling the setting off and on retries it.
        guard attemptedShortcutMode != mode else { return }
        attemptedShortcutMode = mode

        // Re-registering on a mode change matters: press and release mean
        // different things for tap-to-toggle and hold-to-talk.
        let state = platform.hotkey.register(
            .optionSpace,
            onPress: { [weak self] in self?.handleShortcutPress() },
            onRelease: { [weak self] in self?.handleShortcutRelease() }
        )
        isShortcutRegistered = state.isActive

        if case .failed(let reason) = state {
            logger.notice("Global shortcut unavailable: \(reason, privacy: .public)")
        }
    }

    // MARK: - Shortcut handling

    private func handleShortcutPress() {
        guard environment.appState.hasCompletedOnboarding else {
            // Finishing setup has to come first, so surface the window instead
            // of silently starting a dictation the user cannot see.
            platform.menuBar.activateMainWindow()
            return
        }

        switch preferences.hotkeyActivationMode {
        case .toggle:
            if dictation.state.isCapturing {
                finishSession()
            } else {
                beginSession(origin: .systemWide)
            }
        case .holdToTalk:
            guard !dictation.state.isCapturing else { return }
            beginSession(origin: .systemWide)
        }
    }

    private func handleShortcutRelease() {
        guard preferences.hotkeyActivationMode == .holdToTalk else { return }
        guard dictation.state.isCapturing else { return }
        finishSession()
    }

    // MARK: - Session

    private func beginSession(origin: SessionOrigin) {
        guard dictation.state.canStart, sessionTask == nil else { return }

        self.origin = origin
        // Captured before dictation starts: once the overlay appears, the
        // frontmost app can change, and this is the field we must return to.
        targetProcessID = origin == .systemWide
            ? platform.activeApplication.lastExternalApplication?.id
            : nil
        lastInsertion = nil
        overlayDismissTask?.cancel()

        sessionTask = Task { [weak self] in
            await self?.dictation.start()
            self?.sessionTask = nil
        }
    }

    private func finishSession() {
        guard dictation.state.isCapturing else { return }
        let origin = self.origin

        sessionTask?.cancel()
        sessionTask = Task { [weak self] in
            guard let self else { return }
            await dictation.stop()
            sessionTask = nil

            guard origin == .systemWide, dictation.state == .completed,
                  let result = dictation.result
            else {
                // Nothing to deliver. The overlay is held open for system-wide
                // sessions until delivery reports back, so dismiss it here or it
                // would stay on screen indefinitely.
                self.origin = nil
                scheduleOverlayDismissal()
                return
            }
            await deliver(result)
            self.origin = nil
        }
    }

    // MARK: - Delivery

    private func deliver(_ result: DictationResult) async {
        guard preferences.insertTextAutomatically else {
            Clipboard.copy(result.polishedText)
            lastInsertion = .copiedToClipboard(
                reason: "Automatic insertion is turned off in Settings."
            )
            showDeliveryOutcome()
            return
        }

        await activateTargetApplicationIfNeeded()
        let outcome = await platform.textInsertion.insert(
            result.polishedText,
            into: targetProcessID
        )
        lastInsertion = outcome
        logger.info("Delivery outcome: \(outcome.summary, privacy: .public)")
        showDeliveryOutcome()
    }

    /// Carbon hotkeys and the non-activating overlay normally leave the target
    /// app frontmost. This only matters when the user dictated from Dictora's
    /// own window, or when something else stole focus mid-dictation.
    private func activateTargetApplicationIfNeeded() async {
        guard let targetProcessID,
              targetProcessID != NSRunningApplication.current.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != targetProcessID,
              let target = NSRunningApplication(processIdentifier: targetProcessID)
        else { return }

        target.activate()
        // Give the target app a moment to restore its first responder before
        // the Accessibility write or synthetic paste lands.
        try? await Task.sleep(for: .milliseconds(150))
    }

    // MARK: - Overlay

    private func updateOverlay(for snapshot: Snapshot) {
        guard snapshot.showsOverlay else {
            platform.overlay.hide()
            return
        }

        switch snapshot.state {
        case .listening, .transcribing, .processing:
            overlayDismissTask?.cancel()
            platform.overlay.show(
                OverlayPresentation(state: snapshot.state, transcriptPreview: snapshot.transcript)
            )
        case .failed:
            overlayDismissTask?.cancel()
            platform.overlay.show(
                OverlayPresentation(state: snapshot.state, footnote: snapshot.state.error?.errorDescription)
            )
            scheduleOverlayDismissal()
        case .completed:
            // Held open without a footnote until delivery reports its outcome.
            overlayDismissTask?.cancel()
            platform.overlay.show(
                OverlayPresentation(state: snapshot.state, footnote: lastInsertion?.summary)
            )
            if origin != .systemWide { scheduleOverlayDismissal() }
        case .idle, .requestingPermission:
            platform.overlay.hide()
        }
    }

    private func showDeliveryOutcome() {
        guard preferences.showFloatingIndicator else { return }
        platform.overlay.show(
            OverlayPresentation(state: .completed, footnote: lastInsertion?.summary)
        )
        scheduleOverlayDismissal()
    }

    private func scheduleOverlayDismissal() {
        overlayDismissTask?.cancel()
        overlayDismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.overlayLingerDuration)
            guard !Task.isCancelled else { return }
            self?.platform.overlay.hide()
        }
    }
}
#endif
