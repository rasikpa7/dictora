import Foundation
import Testing

@testable import DictoraMac

// MARK: - Network stub

/// Answers every request from a closure, so nothing touches the network.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, body: String)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    nonisolated(unsafe) private static var capturedBodies: [Data] = []

    static func install(_ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            captured = []
            capturedBodies = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { captured } }
    static var bodies: [Data] { lock.withLock { capturedBodies } }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        } else if let httpBody = request.httpBody {
            body = httpBody
        }

        let handler = Self.lock.withLock { () -> Handler? in
            Self.captured.append(request)
            Self.capturedBodies.append(body)
            return Self.handler
        }
        let result: (status: Int, body: String) = handler?(request) ?? (status: 500, body: "{}")
        let response = HTTPURLResponse(
            url: request.url!, statusCode: result.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(result.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let okReply = """
{"id":"msg_1","type":"message","role":"assistant","model":"claude-haiku-5-5",
 "content":[{"type":"thinking","thinking":""},{"type":"text","text":"I want to remove this."}],
 "stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":8}}
"""

private func makeProcessor(key: String? = "sk-ant-test-key-1234567890") -> ClaudeTextProcessor {
    ClaudeTextProcessor(
        client: ClaudeClient(session: StubURLProtocol.makeSession()),
        keyProvider: { key }
    )
}

private let sample = TextProcessingRequest(
    transcript: "I want to remove that, sorry, not that, this",
    style: .professional,
    vocabulary: ["Claude", "Anthropic"],
    claudeModel: .haiku
)

// MARK: - Client and processor

@Suite("Claude client", .serialized)
struct ClaudeClientTests {
    @Test("Sends the right headers and a valid body, without temperature")
    func requestShape() async throws {
        StubURLProtocol.install { _ in (200, okReply) }
        _ = try await makeProcessor().process(sample)

        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test-key-1234567890")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

        let bodyData = try #require(StubURLProtocol.bodies.first)
        let parsed = try JSONSerialization.jsonObject(with: bodyData)
        let body = try #require(parsed as? [String: Any])
        #expect(body["model"] as? String == "claude-haiku-5-5")
        #expect(body["temperature"] == nil)
        #expect((body["max_tokens"] as? Int ?? 0) >= 1024)
        let system = try #require(body["system"] as? String)
        #expect(system.contains("sorry, not that, this"))
        #expect(system.contains("- Claude"))
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect((messages.first?["content"] as? String)?.contains("remove that") == true)
    }

    @Test("Reads only the text blocks, ignoring thinking")
    func readsTextBlocks() async throws {
        StubURLProtocol.install { _ in (200, okReply) }
        let text = try await makeProcessor().process(sample)
        #expect(text == "I want to remove this.")
    }

    @Test("Maps HTTP errors to messages a person can act on", arguments: [
        (401, ClaudeError.invalidKey),
        (403, ClaudeError.forbidden),
        (429, ClaudeError.rateLimited),
        (529, ClaudeError.serviceProblem(529)),
    ])
    func errorMapping(status: Int, expected: ClaudeError) async {
        StubURLProtocol.install { _ in (status, #"{"type":"error","error":{"type":"x","message":"y"}}"#) }
        await #expect(throws: expected) { try await makeProcessor().process(sample) }
    }

    @Test("A refusal or a cut-off reply is an error, not text")
    func refusalAndTruncation() async {
        StubURLProtocol.install { _ in (200, #"{"content":[{"type":"text","text":"no"}],"stop_reason":"refusal"}"#) }
        await #expect(throws: ClaudeError.declined) { try await makeProcessor().process(sample) }

        StubURLProtocol.install { _ in (200, #"{"content":[{"type":"text","text":"cut"}],"stop_reason":"max_tokens"}"#) }
        await #expect(throws: ClaudeError.truncated) { try await makeProcessor().process(sample) }
    }

    @Test("No saved key means unavailable and never touches the network")
    func noKey() async {
        StubURLProtocol.install { _ in (200, okReply) }
        let processor = makeProcessor(key: nil)
        #expect(await processor.availability().isAvailable == false)
        await #expect(throws: ClaudeError.noKey) { try await processor.process(sample) }
        #expect(StubURLProtocol.requests.isEmpty)
    }
}

// MARK: - Fallback chain

@Suite("Claude fallback chain", .serialized)
@MainActor
struct ClaudeChainTests {
    private func makeService(cloud: ClaudeTextProcessor?) -> TextProcessingService {
        TextProcessingService(primary: LocalFallbackTextProcessor(), cloud: cloud)
    }

    @Test("A connected key makes Claude the processor")
    func usesClaude() async throws {
        StubURLProtocol.install { _ in (200, okReply) }
        let result = try await makeService(cloud: makeProcessor()).process(sample)
        #expect(result.processor == .claude)
        #expect(result.text == "I want to remove this.")
    }

    @Test("A bad key falls back to on-device cleanup and says why")
    func badKeyFallsBack() async throws {
        StubURLProtocol.install { _ in (401, "{}") }
        let service = makeService(cloud: makeProcessor())
        let result = try await service.process(sample)

        #expect(result.processor == .localFallback)
        #expect(service.lastCloudIssue?.contains("rejected") == true)
    }

    @Test("Switching Claude off keeps the text on the Mac")
    func switchedOff() async throws {
        StubURLProtocol.install { _ in (200, okReply) }
        var request = sample
        request.useCloud = false
        let result = try await makeService(cloud: makeProcessor()).process(request)

        #expect(result.processor == .localFallback)
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("A slow Claude times out and the dictation still finishes")
    func slowClaude() async throws {
        StubURLProtocol.install { _ in
            Thread.sleep(forTimeInterval: 2)
            return (200, okReply)
        }
        let service = TextProcessingService(
            primary: LocalFallbackTextProcessor(),
            cloud: makeProcessor(),
            cloudTimeout: .milliseconds(300)
        )
        let began = ContinuousClock.now
        let result = try await service.process(sample)

        #expect(result.processor == .localFallback)
        #expect(ContinuousClock.now - began < .seconds(1.5))
    }
}

// MARK: - Keychain, account, prompt, preferences

@Suite("Claude account", .serialized)
@MainActor
struct ClaudeAccountTests {
    private func makeAccount() -> (ClaudeAccount, KeychainStore) {
        let store = KeychainStore(service: "com.dictora.tests.\(UUID().uuidString)", account: "key")
        return (ClaudeAccount(store: store, client: ClaudeClient(session: StubURLProtocol.makeSession())), store)
    }

    @Test("A working key is verified, then saved to the Keychain")
    func connectSavesKey() async {
        StubURLProtocol.install { _ in (200, okReply) }
        let (account, store) = makeAccount()
        defer { store.delete() }

        await account.connect(key: "  sk-ant-valid-key-1234567890  ")
        #expect(account.status == .connected)
        #expect(account.hasKey)
        #expect(store.read() == "sk-ant-valid-key-1234567890")
    }

    @Test("A rejected key is never saved")
    func rejectedKeyNotSaved() async {
        StubURLProtocol.install { _ in (401, "{}") }
        let (account, store) = makeAccount()
        defer { store.delete() }

        await account.connect(key: "sk-ant-wrong-key-1234567890")
        #expect(account.hasKey == false)
        #expect(store.read() == nil)
        if case .failed = account.status {} else { Issue.record("expected failed, got \(account.status)") }
    }

    @Test("Something that isn't a key is caught before any network call")
    func malformedKey() async {
        StubURLProtocol.install { _ in (200, okReply) }
        let (account, _) = makeAccount()
        await account.connect(key: "hello there")
        #expect(StubURLProtocol.requests.isEmpty)
        if case .failed = account.status {} else { Issue.record("expected failed") }
    }

    @Test("A failed re-test keeps the previously saved key")
    func failedRetestKeepsKey() async {
        StubURLProtocol.install { _ in (200, okReply) }
        let (account, store) = makeAccount()
        defer { store.delete() }
        await account.connect(key: "sk-ant-valid-key-1234567890")

        StubURLProtocol.install { _ in (429, "{}") }
        await account.connect(key: "sk-ant-other-key-1234567890")
        #expect(store.read() == "sk-ant-valid-key-1234567890")
        #expect(account.hasKey)
    }

    @Test("Disconnecting removes the key")
    func disconnect() async {
        StubURLProtocol.install { _ in (200, okReply) }
        let (account, store) = makeAccount()
        await account.connect(key: "sk-ant-valid-key-1234567890")
        account.disconnect()
        #expect(store.read() == nil)
        #expect(account.status == .notConnected)
    }
}

@Suite("Claude prompts and settings")
struct ClaudePromptTests {
    @Test("Instructions tell the model to handle self-corrections and use the vocabulary")
    func instructions() {
        let text = PromptBuilder().instructions(for: sample)
        #expect(text.contains("corrects themselves"))
        #expect(text.contains("- Anthropic"))
    }

    @Test("Vocabulary merges built-in names with the user's, without duplicates")
    func vocabulary() {
        let preferences = UserPreferences(customVocabulary: "Naveen, claude\nKubernetes; Dictora")
        #expect(preferences.vocabularyTerms == ["Claude", "Anthropic", "Dictora", "Naveen", "Kubernetes"])
    }

    @Test("Preferences saved before Claude existed still load")
    func oldPreferencesDecode() throws {
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: Data(#"{"playSounds":false}"#.utf8))
        #expect(decoded.useClaude)
        #expect(decoded.claudeModel == .haiku)
        #expect(decoded.playSounds == false)
    }
}

/// A real call to Claude, to check accuracy. Off unless you supply a key:
/// `TEST_RUNNER_DICTORA_TEST_ANTHROPIC_KEY=sk-ant-... xcodebuild test ...`
private let liveKey = ProcessInfo.processInfo.environment["DICTORA_TEST_ANTHROPIC_KEY"]

@Suite("Claude live accuracy")
struct ClaudeLiveTests {
    @Test("Fixes mishearings and self-corrections", .enabled(if: liveKey != nil))
    func realRewrite() async throws {
        let processor = ClaudeTextProcessor(keyProvider: { liveKey })
        let request = TextProcessingRequest(
            transcript: "instead of relying on Apple intelligence they should be able to log into their cloud account and clothes should be able to do the rephrasing. For example I just say sorry not that this this it should be able to understand and correct it",
            style: .natural,
            vocabulary: UserPreferences().vocabularyTerms
        )
        let result = try await processor.process(request)
        print("LIVE CLAUDE: \(result)")
        #expect(result.contains("Claude"))
        #expect(!result.lowercased().contains("clothes"))
    }
}
