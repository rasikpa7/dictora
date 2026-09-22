import Foundation

/// How far the rewriter may stray from the user's original phrasing.
///
/// This is orthogonal to ``WritingStyle``: the style decides *what kind* of
/// text to produce, the strength decides *how much* the text may change.
enum TransformationStrength: String, CaseIterable, Codable, Sendable, Identifiable {
    case minimal
    case balanced
    case rewrite

    var id: String { rawValue }

    static let `default`: TransformationStrength = .balanced

    var displayName: String {
        switch self {
        case .minimal: "Minimal"
        case .balanced: "Balanced"
        case .rewrite: "Rewrite"
        }
    }

    var shortDescription: String {
        switch self {
        case .minimal: "Only fix clear mistakes. Keep my words."
        case .balanced: "Tidy up phrasing while keeping my voice."
        case .rewrite: "Freely restructure sentences for clarity."
        }
    }

    var instruction: String {
        switch self {
        case .minimal:
            """
            Change as little as possible. Only fix unambiguous errors. Keep the \
            user's original sentence structure and word choices.
            """
        case .balanced:
            """
            Improve phrasing and flow where it clearly helps, but keep the \
            user's voice and sentence structure recognisable.
            """
        case .rewrite:
            """
            You may restructure sentences and reorder clauses for clarity, as \
            long as every idea in the original is preserved and nothing is added.
            """
        }
    }
}
