#if os(macOS)
import ApplicationServices
import AppKit
import Foundation
import Observation

/// Tracks whether the user has granted Dictora Accessibility access.
///
/// Accessibility is required both to type into another application's focused
/// field and to listen for the Fn key system-wide. Nothing here reads screen
/// contents — the manager purely reports and requests permission state.
@MainActor
@Observable
final class AccessibilityManager {
    enum Access: Equatable, Sendable {
        case granted
        case notGranted

        var isGranted: Bool { self == .granted }
    }

    private(set) var access: Access = .notGranted
    /// Watching a lone key such as Fn needs Input Monitoring, a separate grant
    /// from Accessibility. Chord shortcuts need neither.
    private(set) var inputMonitoringGranted = false

    private var becomeActiveObserver: NSObjectProtocol?
    private var trustChangeObserver: NSObjectProtocol?
    private var pollTask: Task<Void, Never>?
    private var isMonitoring = false

    init() {
        refresh()
    }

    /// Keeps ``access`` in sync after the user flips the switch in System Settings.
    ///
    /// Ad-hoc debug builds change code signature on every rebuild, so macOS may
    /// still list an *old* Dictora binary as trusted while this one is not —
    /// refreshing on activation and on the Accessibility API notification is
    /// what makes the UI catch up once the correct build is enabled.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        refresh()

        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.refresh()
            }
        }

        trustChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // TCC posts slightly before the new trust state is readable.
            MainActor.assumeIsolated {
                _ = self?.refresh()
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    _ = self?.refresh()
                }
            }
        }

        startPollingWhileDenied()
    }

    func stopMonitoring() {
        if let becomeActiveObserver {
            NotificationCenter.default.removeObserver(becomeActiveObserver)
            self.becomeActiveObserver = nil
        }
        if let trustChangeObserver {
            DistributedNotificationCenter.default().removeObserver(trustChangeObserver)
            self.trustChangeObserver = nil
        }
        pollTask?.cancel()
        pollTask = nil
        isMonitoring = false
    }

    /// Cheap, prompt-free check. Safe to call often.
    @discardableResult
    func refresh() -> Access {
        let granted = AXIsProcessTrusted()
        access = granted ? .granted : .notGranted
        inputMonitoringGranted = CGPreflightListenEventAccess()
        if granted && inputMonitoringGranted {
            pollTask?.cancel()
            pollTask = nil
        } else if isMonitoring {
            startPollingWhileDenied()
        }
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
        if !access.isGranted {
            openSystemSettings()
            startPollingWhileDenied()
        }
        return access
    }

    /// Asks for Input Monitoring, which the Fn shortcut needs. Shows the system
    /// prompt once; after that, the user has to flip the switch in Settings.
    func requestInputMonitoring() {
        if !CGRequestListenEventAccess() {
            openInputMonitoringSettings()
        }
        startPollingWhileDenied()
    }

    func openInputMonitoringSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    /// Clears Dictora's Accessibility entry so the system will prompt again.
    ///
    /// This exists for the case that looks like a bug to the user: System
    /// Settings shows Dictora switched on, but `AXIsProcessTrusted()` says no.
    /// It happens when the running binary no longer matches the one that was
    /// approved — the grant records a code-signing requirement, and an ad-hoc
    /// or re-signed build no longer satisfies it. The stale entry cannot be
    /// fixed by toggling the switch; it has to be removed first.
    ///
    /// - Returns: `nil` on success, or a message to show the user.
    @discardableResult
    func resetPermission() -> String? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return "Dictora has no bundle identifier, so the permission can't be reset."
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleIdentifier]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Couldn't reset the permission automatically. Remove Dictora from System Settings › Privacy & Security › Accessibility, then add it again."
        }

        guard process.terminationStatus == 0 else {
            return "The system refused to reset the permission. Remove Dictora from System Settings › Privacy & Security › Accessibility, then add it again."
        }

        refresh()
        return nil
    }

    /// Deep-links to the Accessibility pane, for when the prompt has already
    /// been dismissed once and will not reappear.
    func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    private func startPollingWhileDenied() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.refresh()
                if self.access.isGranted && self.inputMonitoringGranted { return }
            }
        }
    }
}
#endif
