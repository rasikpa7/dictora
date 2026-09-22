import Foundation

/// Deterministic, offline cleanup used whenever Apple Intelligence is unavailable.
///
/// This intentionally does *less* than a language model: it only applies edits
/// that cannot change meaning, so a user on unsupported hardware still gets a
/// usable transcript rather than an error.
struct LocalFallbackTextProcessor: TextProcessorProtocol {
    let kind: TextProcessorKind = .localFallback

    /// Filler words are only removed when they stand alone as a whole token, to
    /// avoid mangling words that legitimately contain them.
    private static let fillerWords: Set<String> = [
        "um", "uh", "erm", "hmm", "mhm", "uhh", "umm", "er",
    ]

    private static let sentenceTerminators: Set<Character> = [".", "!", "?", ":", ";"]

    func availability() async -> TextProcessorAvailability { .available }

    func process(_ request: TextProcessingRequest) async throws -> String {
        let transcript = request.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw TextProcessingError.emptyTranscript }

        var text = collapseWhitespace(transcript)

        // `.minimal` promises to keep the user's words, so filler removal — the
        // only edit here that deletes anything — is skipped.
        if request.strength != .minimal {
            text = removeFillerWords(from: text)
        }

        text = capitalizeSentences(in: text)
        return addTerminalPunctuation(to: text)
    }

    private func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func removeFillerWords(from text: String) -> String {
        let kept = text.split(separator: " ").filter { token in
            let normalized = token
                .lowercased()
                .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            return !Self.fillerWords.contains(normalized)
        }
        return kept.isEmpty ? text : kept.joined(separator: " ")
    }

    private func capitalizeSentences(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var capitalizeNext = true

        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(contentsOf: String(character).uppercased())
                capitalizeNext = false
            } else {
                result.append(character)
                if Self.sentenceTerminators.contains(character) { capitalizeNext = true }
            }
        }
        return result
    }

    private func addTerminalPunctuation(to text: String) -> String {
        guard let last = text.last else { return text }
        guard last.isLetter || last.isNumber else { return text }
        return text + "."
    }
}
