#if os(macOS)
import AppKit
import Foundation
import Observation
import OSLog
import ServiceManagement

/// Drives "dictate anywhere on the Mac".
///
/// This is the only type that knows the whole Phase 2 flow:
/// global shortcut → remember the app the user was in → dictate → show a
/// status placeholder in the focused field → replace it with the polished text.
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

    /// Where a session is in its life. Tracked here, separately from the
    /// dictation state, because "the user already let go" has to be remembered
    /// while the pipeline is still starting up.
    private enum Phase: Equatable {
        case idle
        /// Permissions, model and microphone are being brought up.
        case starting
        /// Listening.
        case active
        /// Transcribing, rewriting and delivering.
        case finishing
    }

    /// The result of the most recent shortcut-triggered delivery, for the UI.
    private(set) var lastInsertion: TextInsertionOutcome?

    /// The shortcut actually listening right now, which is not necessarily the
    /// one the user picked — Fn silently degrades to a chord without
    /// Accessibility, and the UI needs to say so.
    private(set) var activePreset: ShortcutPreset?
    /// Set when ``activePreset`` differs from the user's choice.
    private(set) var shortcutFallbackReason: String?

    private let environment: AppEnvironment
    private let platform: MacPlatformServices
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "SystemDictation")

    private var origin: SessionOrigin?
    private var targetProcessID: pid_t?
    private var phase: Phase = .idle
    /// Set when the user let go (or tapped to stop) while still starting.
    private var pendingFinish = false
    private var sessionStartedAt: ContinuousClock.Instant?
    /// What the hotkey was last registered *for*, whether or not that
    /// registration succeeded. Guards against repeated registration attempts,
    /// which would otherwise run on every transcript update.
    private var lastRegistrationAttempt: RegistrationAttempt?
    private var isShortcutRegistered = false
    private var lastAppliedLaunchAtLogin: Bool?

    private struct RegistrationAttempt: Equatable {
        var preset: ShortcutPreset
        var mode: HotkeyActivationMode
        /// Fn only works with these grants, so a change must re-register.
        var accessibilityGranted: Bool
        var inputMonitoringGranted: Bool
    }

    /// First press of a potential double-tap to start (idle only).
    private var pendingDoubleTapAt: Date?
    private static let doubleTapWindow: TimeInterval = 0.4
    /// A press shorter than this is an accidental tap, not a dictation.
    private static let minimumSessionLength = Duration.milliseconds(350)

    private var observationTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var overlayDismissTask: Task<Void, Never>?
    private var hasStarted = false

    /// How long a finished overlay stays on screen before fading out.
    private static let overlayLingerDuration = Duration.seconds(2.4)

    init(environment: AppEnvironment, platform: MacPlatformServices) {
        self.environment = environment
        self.platform = platform
    }

    private var dictation: DictationManager { environment.dictation }
    private var preferences: UserPreferences { environment.appState.preferences }

    // MARK: - Lifecycle

    /// Idempotent: called from the main window and from the menu bar item, so
    /// the shortcut works however the app was launched.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        platform.activeApplication.startObserving()
        platform.accessibility.startMonitoring()
        dictation.onCaptureInterrupted = { [weak self] in
            self?.logger.notice("Microphone interrupted; finishing with what was captured")
            self?.finishSession()
        }
        observeState()
        observeMeter()

        // Load the speech model now so the first dictation starts instantly.
        Task { [dictation] in await dictation.warmUp() }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        meterTask?.cancel()
        meterTask = nil
        platform.hotkey.unregister()
        platform.activeApplication.stopObserving()
        platform.accessibility.stopMonitoring()
        platform.overlay.hide()
        dictation.onCaptureInterrupted = nil
        lastRegistrationAttempt = nil
        isShortcutRegistered = false
        activePreset = nil
        shortcutFallbackReason = nil
        pendingDoubleTapAt = nil
        pendingFinish = false
        phase = .idle
        hasStarted = false
    }

    /// Menu bar "Rephrase Clipboard". Rewrites the clipboard in place, so the
    /// user can paste the new version straight back where it came from.
    func rephraseClipboard(as style: WritingStyle) {
        let rewriter = environment.clipboardRewriter
        rewriter.rewriteClipboard(
            style: style,
            strength: preferences.transformationStrength,
            customInstructions: preferences.customInstructions,
            additionalInstructions: preferences.additionalInstructions
        )

        Task { [weak self] in
            guard let self else { return }
            // The menu is already closed by now, so the overlay is the only way
            // to report progress and completion.
            showOverlay(OverlayPresentation(state: .processing, footnote: "Rephrasing clipboard"))

            while rewriter.state.isWorking {
                try? await Task.sleep(for: .milliseconds(80))
            }

            switch rewriter.state {
            case .finished:
                rewriter.copyResultToClipboard()
                showOverlay(
                    OverlayPresentation(state: .completed, footnote: "Rephrased · copied to clipboard")
                )
            case .failed(let message):
                showOverlay(OverlayPresentation(state: .completed, footnote: message))
            case .idle, .working:
                platform.overlay.hide()
                return
            }
            scheduleOverlayDismissal()
        }
    }

    private func showOverlay(_ presentation: OverlayPresentation) {
        guard preferences.showFloatingIndicator else { return }
        overlayDismissTask?.cancel()
        platform.overlay.show(presentation)
    }

    /// Menu bar "Start Dictation". Behaves like the global shortcut: the result
    /// goes back to the app the user was in before opening the menu.
    func toggleFromMenuBar() {
        switch phase {
        case .starting, .active:
            finishSession()
        case .idle:
            beginSession(origin: .systemWide)
        case .finishing:
            break
        }
    }

    // MARK: - Reconciliation

    /// Everything the coordinator reacts to, gathered in one observable read.
    ///
    /// The live voice meter is deliberately absent: it changes ~30 times a
    /// second and only the overlay cares, so it has its own loop.
    private struct Snapshot: Equatable, Sendable {
        var state: DictationState
        var modelNote: String?
        var shortcutEnabled: Bool
        var shortcutPreset: ShortcutPreset
        var activationMode: HotkeyActivationMode
        var showsOverlay: Bool
        var accessibilityGranted: Bool
        var inputMonitoringGranted: Bool
        var launchAtLogin: Bool
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(
            state: dictation.state,
            modelNote: dictation.speechModel.note,
            shortcutEnabled: preferences.globalShortcutEnabled,
            shortcutPreset: preferences.shortcutPreset,
            activationMode: preferences.hotkeyActivationMode,
            showsOverlay: preferences.showFloatingIndicator,
            accessibilityGranted: platform.accessibility.access.isGranted,
            inputMonitoringGranted: platform.accessibility.inputMonitoringGranted,
            launchAtLogin: preferences.launchAtLogin
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

    /// What the overlay shows while listening: the voice bars and the words so far.
    private struct LiveReading: Equatable, Sendable {
        var meter: VoiceMeterReading
        var text: String
    }

    /// Feeds the live bars and words without waking the rest of the coordinator.
    private func observeMeter() {
        let readings = Observations { [weak self] in
            self.map { LiveReading(meter: $0.dictation.voiceMeter, text: $0.dictation.transcript.displayText) }
        }

        meterTask = Task { [weak self] in
            for await reading in readings {
                guard !Task.isCancelled else { return }
                guard let self, let reading,
                      dictation.state == .listening,
                      preferences.showFloatingIndicator
                else { continue }
                platform.overlay.show(
                    OverlayPresentation(state: .listening, voiceMeter: reading.meter, text: reading.text)
                )
            }
        }
    }

    private func apply(_ snapshot: Snapshot?) {
        guard let snapshot else { return }

        // The pipeline can end a session on its own (an error mid-capture).
        if phase == .active, !snapshot.state.isCapturing {
            phase = .idle
            origin = nil
        }

        reconcileShortcut(
            enabled: snapshot.shortcutEnabled,
            preset: snapshot.shortcutPreset,
            mode: snapshot.activationMode,
            accessibilityGranted: snapshot.accessibilityGranted,
            inputMonitoringGranted: snapshot.inputMonitoringGranted
        )
        applyLaunchAtLogin(snapshot.launchAtLogin)
        updateOverlay(for: snapshot)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard lastAppliedLaunchAtLogin != enabled else { return }
        lastAppliedLaunchAtLogin = enabled

        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            logger.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reconcileShortcut(
        enabled: Bool,
        preset: ShortcutPreset,
        mode: HotkeyActivationMode,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool
    ) {
        guard enabled else {
            if lastRegistrationAttempt != nil {
                platform.hotkey.unregister()
                lastRegistrationAttempt = nil
                isShortcutRegistered = false
                activePreset = nil
                shortcutFallbackReason = nil
            }
            return
        }

        // Attempted once per combination, including after a failure, so a
        // conflicting shortcut doesn't retry on every transcript update.
        let attempt = RegistrationAttempt(
            preset: preset,
            mode: mode,
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: inputMonitoringGranted
        )
        guard lastRegistrationAttempt != attempt else { return }
        lastRegistrationAttempt = attempt

        var state = platform.hotkey.register(
            preset.shortcut,
            onPress: { [weak self] in self?.handleShortcutPress() },
            onRelease: { [weak self] in self?.handleShortcutRelease() }
        )

        if state.isActive {
            activePreset = preset
            shortcutFallbackReason = nil
        } else if preset != .fallback {
            // Rather than leaving the user with no way to dictate from other
            // apps, fall back to a chord that needs no Accessibility — and say
            // so, so the degraded state is visible instead of mysterious.
            let reason = state.failureReason
            logger.notice("\(preset.displayString, privacy: .public) unavailable: \(reason ?? "", privacy: .public)")

            state = platform.hotkey.register(
                ShortcutPreset.fallback.shortcut,
                onPress: { [weak self] in self?.handleShortcutPress() },
                onRelease: { [weak self] in self?.handleShortcutRelease() }
            )
            activePreset = state.isActive ? .fallback : nil
            shortcutFallbackReason = state.isActive ? reason : nil
        } else {
            activePreset = nil
            shortcutFallbackReason = nil
        }

        isShortcutRegistered = state.isActive
    }

    // MARK: - Shortcut handling

    func handleShortcutPress() {
        guard environment.appState.hasCompletedOnboarding else {
            platform.menuBar.activateMainWindow()
            return
        }

        switch preferences.hotkeyActivationMode {
        case .doubleTap:
            handleDoubleTapPress()
        case .holdToTalk:
            pendingDoubleTapAt = nil
            if phase == .idle { beginSession(origin: .systemWide) }
        }
    }

    func handleShortcutRelease() {
        guard preferences.hotkeyActivationMode == .holdToTalk else { return }
        // Also valid while still starting: the release is remembered and honoured
        // the moment listening begins.
        finishSession()
    }

    private func handleDoubleTapPress() {
        // While a session is running, one press stops it — no second tap needed.
        // Starting still requires a double-tap so a single accidental press
        // does not begin dictation.
        if phase == .starting || phase == .active {
            pendingDoubleTapAt = nil
            finishSession()
            return
        }

        let now = Date()
        if let pendingDoubleTapAt,
           now.timeIntervalSince(pendingDoubleTapAt) <= Self.doubleTapWindow {
            self.pendingDoubleTapAt = nil
            beginSession(origin: .systemWide)
        } else {
            pendingDoubleTapAt = now
        }
    }

    // MARK: - Session

    private func beginSession(origin: SessionOrigin) {
        guard phase == .idle, dictation.state.canStart else { return }

        phase = .starting
        pendingFinish = false
        self.origin = origin
        sessionStartedAt = .now
        // Captured before dictation starts: once the overlay appears, the
        // frontmost app can change, and this is the field we must return to.
        targetProcessID = origin == .systemWide
            ? platform.activeApplication.lastExternalApplication?.id
            : nil
        lastInsertion = nil
        overlayDismissTask?.cancel()

        sessionTask = Task { [weak self] in
            guard let self else { return }
            await dictation.start()
            sessionTask = nil

            guard phase == .starting else { return }
            guard dictation.state.isCapturing else {
                // Failed to start; the overlay reports why.
                phase = .idle
                self.origin = nil
                pendingFinish = false
                return
            }
            phase = .active
            if pendingFinish {
                // The user let go while we were still starting.
                pendingFinish = false
                finishSession()
            }
        }
    }

    /// Ends the current session, whichever stage it is in.
    private func finishSession() {
        switch phase {
        case .idle, .finishing:
            return
        case .starting:
            pendingFinish = true
            return
        case .active:
            break
        }

        phase = .finishing
        let origin = self.origin
        let heldFor = sessionStartedAt.map { ContinuousClock.now - $0 } ?? .seconds(1)

        sessionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                sessionTask = nil
                phase = .idle
                self.origin = nil
            }

            guard heldFor >= Self.minimumSessionLength else {
                // An accidental tap: end quietly, with no error and no text.
                logger.info("Session ended after \(heldFor.components.attoseconds / 1_000_000_000_000_000, privacy: .public) ms; treated as a tap")
                await dictation.cancel()
                platform.overlay.hide()
                return
            }

            await dictation.stop()

            guard origin == .systemWide, dictation.state == .completed,
                  let result = dictation.result
            else {
                scheduleOverlayDismissal()
                return
            }
            await deliver(result)
        }
    }

    // MARK: - Delivery

    private func deliver(_ result: DictationResult) async {
        guard preferences.insertTextAutomatically else {
            Clipboard.copy(result.polishedText)
            lastInsertion = .copiedToClipboard(
                reason: "Automatic insertion is turned off in Settings."
            )
            showDeliveryOutcome(for: result)
            return
        }

        await activateTargetApplicationIfNeeded()

        var outcome = await platform.textInsertion.insert(
            result.polishedText,
            into: targetProcessID
        )
        if case .failed = outcome {
            // Never end with the words nowhere. The clipboard is the last resort.
            Clipboard.copy(result.polishedText)
            outcome = .copiedToClipboard(reason: "Dictora couldn't type into this app, so the text is on your clipboard.")
        }
        lastInsertion = outcome
        logger.info("Delivery outcome: \(outcome.summary, privacy: .public)")
        showDeliveryOutcome(for: result)
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
        try? await Task.sleep(for: .milliseconds(150))
    }

    // MARK: - Overlay

    private func updateOverlay(for snapshot: Snapshot) {
        guard snapshot.showsOverlay else {
            platform.overlay.hide()
            return
        }

        switch snapshot.state {
        case .requestingPermission:
            overlayDismissTask?.cancel()
            platform.overlay.show(
                OverlayPresentation(state: snapshot.state, footnote: snapshot.modelNote)
            )
        case .listening:
            overlayDismissTask?.cancel()
            platform.overlay.show(
                OverlayPresentation(
                    state: snapshot.state,
                    voiceMeter: dictation.voiceMeter,
                    text: dictation.transcript.displayText
                )
            )
        case .transcribing, .processing:
            overlayDismissTask?.cancel()
            platform.overlay.show(
                OverlayPresentation(state: snapshot.state, text: dictation.transcript.displayText)
            )
        case .failed:
            overlayDismissTask?.cancel()
            platform.overlay.show(
                OverlayPresentation(state: snapshot.state, footnote: snapshot.state.error?.errorDescription)
            )
            scheduleOverlayDismissal()
        case .completed:
            // A shortcut dictation is still being delivered; the delivery
            // outcome ("Inserted") is what the user should see, not a bare "Done".
            if origin == .systemWide, lastInsertion == nil { return }
            overlayDismissTask?.cancel()
            platform.overlay.show(
                OverlayPresentation(
                    state: snapshot.state,
                    footnote: lastInsertion?.summary,
                    text: dictation.result?.polishedText
                )
            )
            if origin != .systemWide { scheduleOverlayDismissal() }
        case .idle:
            platform.overlay.hide()
        }
    }

    private func showDeliveryOutcome(for result: DictationResult) {
        guard preferences.showFloatingIndicator else { return }
        var footnote = lastInsertion?.summary
        if result.warning != nil { footnote = [footnote, "as spoken"].compactMap { $0 }.joined(separator: " · ") }
        platform.overlay.show(
            OverlayPresentation(state: .completed, footnote: footnote, text: result.polishedText)
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
