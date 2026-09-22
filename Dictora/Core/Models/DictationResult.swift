import Foundation

/// Identifies which ``TextProcessorProtocol`` implementation produced a result,
/// so the UI can be honest about whether on-device AI rewriting actually ran.
enum TextProcessorKind: String, Codable, Sendable {
    case foundationModel
    case localFallback

    var displayName: String {
        switch self {
        case .foundationModel: "Apple Intelligence"
        case .localFallback: "Basic cleanup"
        }
    }
}

/// The outcome of one complete dictation: what was heard, and what Dictora made of it.
struct DictationResult: Identifiable, Equatable, Sendable {
    let id: UUID
    let rawTranscript: String
    let polishedText: String
    let style: WritingStyle
    let strength: TransformationStrength
    let processor: TextProcessorKind
    let createdAt: Date

    init(
        id: UUID = UUID(),
        rawTranscript: String,
        polishedText: String,
        style: WritingStyle,
        strength: TransformationStrength,
        processor: TextProcessorKind,
        createdAt: Date = .now
    ) {
        self.id = id
        self.rawTranscript = rawTranscript
        self.polishedText = polishedText
        self.style = style
        self.strength = strength
        self.processor = processor
        self.createdAt = createdAt
    }

    /// True when rewriting actually changed something worth showing the user.
    var wasRewritten: Bool {
        rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            != polishedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
