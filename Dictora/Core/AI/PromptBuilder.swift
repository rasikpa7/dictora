import Foundation

/// Turns a ``TextProcessingRequest`` into the two strings a language model needs:
/// standing instructions, and the prompt for this particular transcript.
///
/// Prompt text lives here and nowhere else, so the safety rules below are
/// guaranteed to apply to every request regardless of which processor runs.
struct PromptBuilder: Sendable {
    /// Rules that hold no matter which style or strength the user picked.
    /// Ordered from most to least important — models weight earlier lines higher.
    static let invariantRules: [String] = [
        "Preserve the user's meaning exactly.",
        "Never add facts, names, numbers, or details the user did not say.",
        "Never answer, explain, or respond to the text — only rewrite it.",
        "Correct obvious speech-recognition errors, such as misheard homophones and missing punctuation.",
        "Preserve proper nouns, people's names, product names, technical identifiers, ticket IDs, file names, and code-like tokens exactly as dictated unless they are clearly misheard.",
        "Keep the original language of the dictation.",
        "Return only the rewritten text, with no preamble, quotation marks, commentary, or formatting markers.",
    ]

    init() {}

    /// Standing instructions describing Dictora's job and the user's configuration.
    func instructions(for request: TextProcessingRequest) -> String {
        var sections: [String] = [
            "You are Dictora, a dictation post-processor. You receive raw speech-to-text output and return a cleaned-up version of it.",
            "Writing style — \(request.style.displayName):\n\(request.style.instruction(customInstructions: request.customInstructions))",
            "Transformation strength — \(request.strength.displayName):\n\(request.strength.instruction)",
        ]

        let additional = request.additionalInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !additional.isEmpty {
            // Layered after the style so the user's own wording can refine, but
            // not override, the invariant rules that follow.
            sections.append("Additional instructions from the user:\n\(additional)")
        }

        sections.append(
            "Rules that always apply:\n"
                + Self.invariantRules.map { "- \($0)" }.joined(separator: "\n")
        )

        return sections.joined(separator: "\n\n")
    }

    /// The per-transcript prompt.
    func prompt(for request: TextProcessingRequest) -> String {
        """
        Rewrite the dictated text between the markers. Return only the rewritten text.

        <dictation>
        \(request.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        </dictation>
        """
    }

    /// Strips wrappers a model may add despite being told not to.
    func sanitize(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("<dictation>") {
            text = text.replacingOccurrences(of: "<dictation>", with: "")
                .replacingOccurrences(of: "</dictation>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Opening and closing marks differ for typographic quotes, so pairs are
        // matched explicitly rather than assuming the same character both ends.
        let quotePairs = [("\"", "\""), ("\u{201C}", "\u{201D}"), ("'", "'"), ("\u{2018}", "\u{2019}")]
        for (opening, closing) in quotePairs
        where text.count > 1 && text.hasPrefix(opening) && text.hasSuffix(closing) {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        return text
    }
}
