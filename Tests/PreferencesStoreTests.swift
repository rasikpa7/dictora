import Foundation
import Testing

#if os(macOS)
@testable import DictoraMac
#else
@testable import DictoraiOS
#endif

@Suite("Preferences storage")
struct PreferencesStoreTests {
    /// Each test gets its own suite name so runs never share state.
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "com.dictora.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return defaults
    }

    @Test("An empty store returns the shipped defaults")
    func emptyStoreReturnsDefaults() throws {
        let store = UserDefaultsPreferencesStore(defaults: try makeDefaults())
        let preferences = store.load()

        #expect(preferences.hasCompletedOnboarding == false)
        #expect(preferences.selectedWritingStyle == .professional)
        #expect(preferences.transformationStrength == .balanced)
        #expect(preferences.playSounds)
        #expect(preferences.customInstructions.isEmpty)
    }

    @Test("Saved preferences round-trip")
    func preferencesRoundTrip() throws {
        let defaults = try makeDefaults()
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        var preferences = UserPreferences()
        preferences.hasCompletedOnboarding = true
        preferences.selectedWritingStyle = .developer
        preferences.additionalInstructions = "Never change ticket IDs."
        preferences.transformationStrength = .rewrite
        preferences.playSounds = false
        store.save(preferences)

        let reloaded = UserDefaultsPreferencesStore(defaults: defaults).load()
        #expect(reloaded == preferences)
    }

    @Test("Corrupt stored data falls back to defaults instead of throwing")
    func corruptDataFallsBack() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: UserDefaultsPreferencesStore.storageKey)

        let preferences = UserDefaultsPreferencesStore(defaults: defaults).load()
        #expect(preferences == UserPreferences())
    }

    @Test("Preferences written by a build without a key still decode")
    func partialPayloadDecodes() throws {
        let partial = Data(#"{"selectedWritingStyle":"natural"}"#.utf8)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: partial)

        #expect(decoded.selectedWritingStyle == .natural)
        #expect(decoded.transformationStrength == .balanced)
        #expect(decoded.hasCompletedOnboarding == false)
    }

    @Test("Custom style without instructions is an invalid configuration")
    func customStyleNeedsInstructions() {
        var preferences = UserPreferences(selectedWritingStyle: .custom)
        #expect(!preferences.isWritingConfigurationValid)

        preferences.customInstructions = "Write like a changelog."
        #expect(preferences.isWritingConfigurationValid)
    }

    @Test("Presets are always a valid configuration")
    func presetsAreAlwaysValid() {
        for style in WritingStyle.allCases where style != .custom {
            #expect(UserPreferences(selectedWritingStyle: style).isWritingConfigurationValid)
        }
    }

    @Test("The in-memory store keeps values without touching UserDefaults")
    func inMemoryStoreRoundTrips() {
        let store = InMemoryPreferencesStore()
        var preferences = store.load()
        preferences.hasCompletedOnboarding = true
        store.save(preferences)

        #expect(store.load().hasCompletedOnboarding)
    }
}
