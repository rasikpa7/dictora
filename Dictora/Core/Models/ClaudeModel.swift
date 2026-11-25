import Foundation

/// The Claude models Dictora offers for rewriting.
///
/// Rewriting a sentence is a small, latency-sensitive job, so the default is the
/// fastest model. Raw values are the exact API model IDs.
enum ClaudeModel: String, CaseIterable, Codable, Sendable, Identifiable {
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"

    var id: String { rawValue }

    static let `default`: ClaudeModel = .haiku

    var displayName: String {
        switch self {
        case .haiku: "Claude Haiku 5.5"
        case .sonnet: "Claude Sonnet 5.5"
        }
    }

    var detail: String {
        switch self {
        case .haiku: "Fastest and cheapest. Right for almost every dictation."
        case .sonnet: "A little slower, better with long or tricky dictations."
        }
    }
}
