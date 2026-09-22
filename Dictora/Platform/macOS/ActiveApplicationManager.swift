#if os(macOS)
import AppKit
import Foundation
import Observation

/// Identity of an application other than Dictora.
struct ForegroundApplication: Equatable, Sendable, Identifiable {
    let id: pid_t
    let bundleIdentifier: String?
    let localizedName: String?

    var displayName: String { localizedName ?? bundleIdentifier ?? "Unknown app" }
}

/// Reports which application the user was last working in.
///
/// Needed so that text insertion (Phase 2) targets the app the user came from,
/// not Dictora itself — activating Dictora's own overlay would otherwise make
/// Dictora the frontmost app.
@MainActor
@Observable
final class ActiveApplicationManager {
    private(set) var frontmostApplication: ForegroundApplication?
    /// The last frontmost app that was not Dictora. This is the insertion target.
    private(set) var lastExternalApplication: ForegroundApplication?

    private var observer: (any NSObjectProtocol)?
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        update(with: workspace.frontmostApplication)
    }

    /// Observation is torn down in ``stopObserving()`` rather than `deinit`,
    /// which cannot touch main-actor state. In practice this manager lives for
    /// the lifetime of the app.
    func startObserving() {
        guard observer == nil else { return }
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.update(with: application)
            }
        }
    }

    func stopObserving() {
        guard let observer else { return }
        workspace.notificationCenter.removeObserver(observer)
        self.observer = nil
    }

    private func update(with application: NSRunningApplication?) {
        guard let application else { return }
        let descriptor = ForegroundApplication(
            id: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName
        )
        frontmostApplication = descriptor

        if descriptor.id != ProcessInfo.processInfo.processIdentifier {
            lastExternalApplication = descriptor
        }
    }
}
#endif
