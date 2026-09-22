import Foundation
import Testing

#if os(macOS)
@testable import DictoraMac
#else
@testable import DictoraiOS
#endif

@Suite("PromptBuilder")
struct PromptBuilderTests {
    private let builder = PromptBuilder()

    private func request(
        transcript: String = "hey naveen i fixed that issue you can check latest build",
        style: WritingStyle = .professional,
        customInstructions: String = "",
        additionalInstructions: String = "",
        strength: TransformationStrength = .balanced
    ) -> TextProcessingRequest {
        TextProcessingRequest(
            transcript: transcript,
            style: style,
            customInstructions: customInstructions,
            additionalInstructions: additionalInstructions,
            strength: strength
        )
    }

    @Test("Every invariant safety rule appears in the instructions")
    func invariantRulesAlwaysPresent() {
        for style in WritingStyle.allCases {
            for strength in TransformationStrength.allCases {
                let instructions = builder.instructions(
                    for: request(style: style, customInstructions: "Be terse.", strength: strength)
                )
                for rule in PromptBuilder.invariantRules {
                    #expect(instructions.contains(rule), "\(style)/\(strength) dropped: \(rule)")
                }
            }
        }
    }

    @Test("Instructions carry the selected style and strength")
    func instructionsIncludeStyleAndStrength() {
        let instructions = builder.instructions(for: request(style: .developer, strength: .minimal))
        #expect(instructions.contains(WritingStyle.developer.baseInstruction))
        #expect(instructions.contains(TransformationStrength.minimal.instruction))
        #expect(instructions.contains("Developer"))
    }

    @Test("Additional instructions layer on top of a preset style")
    func additionalInstructionsCombineWithPreset() {
        let additional = "Never change ticket IDs, API names, variable names, class names, or filenames."
        let instructions = builder.instructions(
            for: request(style: .developer, additionalInstructions: additional)
        )
        #expect(instructions.contains(additional))
        #expect(instructions.contains(WritingStyle.developer.baseInstruction))
    }

    @Test("Blank additional instructions add no empty section")
    func blankAdditionalInstructionsAreOmitted() {
        let instructions = builder.instructions(for: request(additionalInstructions: "   \n  "))
        #expect(!instructions.contains("Additional instructions from the user:"))
    }

    @Test("Custom style instructions reach the model")
    func customInstructionsReachTheModel() {
        let instructions = builder.instructions(
            for: request(style: .custom, customInstructions: "Write like a changelog entry.")
        )
        #expect(instructions.contains("Write like a changelog entry."))
    }

    @Test("The prompt wraps the transcript in markers")
    func promptWrapsTranscript() {
        let transcript = "hey naveen i fixed that issue"
        let prompt = builder.prompt(for: request(transcript: transcript))
        #expect(prompt.contains("<dictation>"))
        #expect(prompt.contains("</dictation>"))
        #expect(prompt.contains(transcript))
    }

    @Test(
        "Sanitising removes wrappers a model might add",
        arguments: [
            ("  Hello there.  ", "Hello there."),
            ("\"Hello there.\"", "Hello there."),
            ("\u{201C}Hello there.\u{201D}", "Hello there."),
            ("<dictation>Hello there.</dictation>", "Hello there."),
            ("Hello there.", "Hello there."),
        ]
    )
    func sanitizeStripsWrappers(input: String, expected: String) {
        #expect(builder.sanitize(input) == expected)
    }

    @Test("Sanitising leaves an apostrophe-only string intact")
    func sanitizeHandlesShortStrings() {
        #expect(builder.sanitize("'") == "'")
    }
}
