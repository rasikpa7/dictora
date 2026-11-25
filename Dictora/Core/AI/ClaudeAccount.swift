import Foundation
import Observation

/// The user's connection to Claude: whether a key is saved, and whether it works.
///
/// The key is kept in the Keychain. This object only ever holds whether one
/// exists, so the key can't leak through state, logs or previews.
@MainActor
@Observable
final class ClaudeAccount {
    enum Status: Equatable {
        case notConnected
        case checking
        case connected
        case failed(String)
    }

    private(set) var status: Status
    /// Whether a key is saved in the Keychain, independent of the last test result.
    private(set) var hasKey: Bool
    private let store: KeychainStore
    private let client: ClaudeClient

    init(store: KeychainStore = KeychainStore(), client: ClaudeClient = ClaudeClient()) {
        self.store = store
        self.client = client
        let saved = store.read() != nil
        self.hasKey = saved
        self.status = saved ? .connected : .notConnected
    }

    /// Cheap check on the format only, so obvious paste mistakes get a clear
    /// message before any network call.
    static func looksLikeKey(_ candidate: String) -> Bool {
        let key = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.hasPrefix("sk-ant-") && key.count > 20 && !key.contains(" ")
    }

    /// Verifies the key with a tiny request and keeps it only if it works.
    func connect(key candidate: String) async {
        let key = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeKey(key) else {
            status = .failed("That doesn't look like an Anthropic API key. Keys start with sk-ant-.")
            return
        }

        status = .checking
        do {
            _ = try await client.complete(
                apiKey: key,
                model: .default,
                system: "Reply with the single word OK.",
                user: "Ping",
                maxTokens: 64
            )
            guard store.write(key) else {
                status = .failed("The key works, but macOS wouldn't save it to the Keychain.")
                return
            }
            hasKey = true
            status = .connected
        } catch {
            // A bad key or a network problem must never replace a good saved key.
            status = .failed(hasKey
                ? error.localizedDescription + " Your previously saved key is unchanged."
                : error.localizedDescription)
        }
    }

    /// Re-tests the saved key, for the "Test connection" button.
    func testSavedKey() async {
        guard let key = store.read() else {
            hasKey = false
            status = .notConnected
            return
        }
        await connect(key: key)
    }

    func disconnect() {
        store.delete()
        hasKey = false
        status = .notConnected
    }
}
