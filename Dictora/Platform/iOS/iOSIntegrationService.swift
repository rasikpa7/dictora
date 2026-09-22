#if os(iOS)
import Foundation
import Observation
import UIKit

/// iOS-side integration surface.
///
/// iOS has no equivalent of the macOS system-wide insertion capability, and
/// Dictora does not pretend otherwise: polished text leaves the app only when
/// the user copies or shares it.
///
/// The reserved identifiers below are the seams for the two extensions on the
/// roadmap. Neither extension exists yet, and the App Group is **not** enabled
/// in the entitlements — adding either is a deliberate future step, documented
/// in README.md.
@MainActor
@Observable
final class IOSIntegrationService {
    /// Identifiers reserved for future extension targets.
    enum FutureIntegration {
        /// Add to both app and extension entitlements before use.
        static let appGroupIdentifier = "group.com.dictora.app"
        static let keyboardExtensionBundleSuffix = "keyboard"
        static let shareExtensionBundleSuffix = "share"
    }

    private(set) var lastCopiedText: String?

    init() {}

    /// The only supported way text leaves Dictora on iOS today.
    func copy(_ text: String) {
        Clipboard.copy(text)
        lastCopiedText = text
    }

    /// Whether the device can present a share sheet for the given text.
    func canShare(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Opens Dictora's page in Settings so the user can change permissions.
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif
