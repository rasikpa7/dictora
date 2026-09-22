import Foundation
import OSLog

/// Persistence boundary for ``UserPreferences``.
///
/// Deliberately tiny: the app needs load and save, nothing else. Swapping in a
/// file-backed or synced store later means conforming a new type, not changing
/// call sites.
protocol PreferencesStoring: Sendable {
    func load() -> UserPreferences
    func save(_ preferences: UserPreferences)
}

/// Stores the whole preferences struct as one JSON blob in `UserDefaults`.
///
/// A single key avoids the drift that happens when a dozen loose keys are read
/// and written from different places.
///
/// `@unchecked Sendable` because `UserDefaults` is not marked `Sendable` even
/// though Apple documents it as thread-safe; every other stored property here
/// is immutable.
final class UserDefaultsPreferencesStore: PreferencesStoring, @unchecked Sendable {
    static let storageKey = "com.dictora.preferences.v1"

    private let defaults: UserDefaults
    private let key: String
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "PreferencesStore")

    init(defaults: UserDefaults = .standard, key: String = UserDefaultsPreferencesStore.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> UserPreferences {
        guard let data = defaults.data(forKey: key) else { return UserPreferences() }
        do {
            return try JSONDecoder().decode(UserPreferences.self, from: data)
        } catch {
            logger.error("Falling back to default preferences: \(error.localizedDescription, privacy: .public)")
            return UserPreferences()
        }
    }

    func save(_ preferences: UserPreferences) {
        do {
            defaults.set(try JSONEncoder().encode(preferences), forKey: key)
        } catch {
            logger.error("Could not persist preferences: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Non-persistent store for tests and SwiftUI previews.
final class InMemoryPreferencesStore: PreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var preferences: UserPreferences

    init(_ preferences: UserPreferences = UserPreferences()) {
        self.preferences = preferences
    }

    func load() -> UserPreferences {
        lock.withLock { preferences }
    }

    func save(_ preferences: UserPreferences) {
        lock.withLock { self.preferences = preferences }
    }
}
