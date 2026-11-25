import Foundation
import OSLog

/// Why a call to Claude failed, in words a person can act on.
enum ClaudeError: LocalizedError, Equatable, Sendable {
    case noKey
    case invalidKey
    case forbidden
    case rateLimited
    case serviceProblem(Int)
    case network(String)
    case declined
    case truncated
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey: "No Claude API key is connected."
        case .invalidKey: "Claude rejected the API key. Check it and try again."
        case .forbidden: "This API key isn't allowed to use that model."
        case .rateLimited: "Claude is rate limiting this key right now."
        case .serviceProblem(let code): "Claude is having trouble right now (error \(code))."
        case .network(let detail): "Couldn't reach Claude: \(detail)"
        case .declined: "Claude declined to rewrite this text."
        case .truncated: "Claude's reply was cut off."
        case .badResponse: "Claude sent a reply Dictora couldn't read."
        }
    }
}

/// A minimal client for the Anthropic Messages API.
///
/// Raw HTTP on purpose: Dictora needs a single non-streaming call, and there is
/// no official Swift SDK. Kept separate from the processor so the connection
/// test in Settings and the rewrite use exactly the same code.
struct ClaudeClient: Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"

    var session: URLSession
    var endpoint: URL

    init(session: URLSession = .claudeDefault, endpoint: URL = ClaudeClient.endpoint) {
        self.session = session
        self.endpoint = endpoint
    }

    func complete(
        apiKey: String,
        model: ClaudeModel,
        system: String,
        user: String,
        maxTokens: Int
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        // No `temperature`: current models reject non-default sampling values.
        // Low effort keeps a one-sentence rewrite fast.
        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": ["effort": "low"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClaudeError.network((error as? URLError)?.localizedDescription ?? error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(forStatus: http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else { throw ClaudeError.badResponse }

        switch json["stop_reason"] as? String {
        case "refusal": throw ClaudeError.declined
        case "max_tokens": throw ClaudeError.truncated
        default: break
        }

        // Replies can include thinking blocks; only the text blocks are the answer.
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else { throw ClaudeError.badResponse }
        return text
    }

    static func error(forStatus status: Int) -> ClaudeError {
        switch status {
        case 401: .invalidKey
        case 403: .forbidden
        case 429: .rateLimited
        default: .serviceProblem(status)
        }
    }
}

extension URLSession {
    /// No caching and no cookies: a dictation must never be stored by the
    /// URL loading system.
    static let claudeDefault: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
}

/// Rewrites a transcript with Claude, using the user's own API key.
struct ClaudeTextProcessor: TextProcessorProtocol {
    let kind: TextProcessorKind = .claude

    private let client: ClaudeClient
    private let keyProvider: @Sendable () -> String?
    private let promptBuilder: PromptBuilder
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "ClaudeTextProcessor")

    init(
        client: ClaudeClient = ClaudeClient(),
        promptBuilder: PromptBuilder = PromptBuilder(),
        keyProvider: @escaping @Sendable () -> String? = { KeychainStore().read() }
    ) {
        self.client = client
        self.promptBuilder = promptBuilder
        self.keyProvider = keyProvider
    }

    func availability() async -> TextProcessorAvailability {
        keyProvider() == nil
            ? .unavailable("Connect a Claude API key in Settings to use Claude.")
            : .available
    }

    func process(_ request: TextProcessingRequest) async throws -> String {
        let transcript = request.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw TextProcessingError.emptyTranscript }
        guard let key = keyProvider() else { throw ClaudeError.noKey }

        // Room for the rewrite of a long dictation, never less than a few lines.
        let maxTokens = min(8192, max(1024, transcript.count))

        let reply = try await client.complete(
            apiKey: key,
            model: request.claudeModel,
            system: promptBuilder.instructions(for: request),
            user: promptBuilder.prompt(for: request),
            maxTokens: maxTokens
        )
        let cleaned = promptBuilder.sanitize(reply)
        // An empty result must never destroy the user's words.
        return cleaned.isEmpty ? transcript : cleaned
    }
}
