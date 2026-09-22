import Foundation
import Testing

#if os(macOS)
@testable import DictoraMac
#else
@testable import DictoraiOS
#endif

@Suite("WritingStyle")
struct WritingStyleTests {
    @Test("Every style has display text and a base instruction")
    func everyStyleIsFullyDescribed() {
        for style in WritingStyle.allCases {
            #expect(!style.displayName.isEmpty)
            #expect(!style.shortDescription.isEmpty)
            #expect(!style.baseInstruction.isEmpty)
            #expect(!style.symbolName.isEmpty)
        }
    }

    @Test("Raw values are stable, because preferences persist them")
    func rawValuesAreStable() {
        #expect(WritingStyle.grammarOnly.rawValue == "grammarOnly")
        #expect(WritingStyle.professional.rawValue == "professional")
        #expect(WritingStyle.developer.rawValue == "developer")
        #expect(WritingStyle.natural.rawValue == "natural")
        #expect(WritingStyle.custom.rawValue == "custom")
    }

    @Test("Only the custom style requires user instructions")
    func onlyCustomRequiresInstructions() {
        #expect(WritingStyle.custom.requiresCustomInstructions)
        for style in WritingStyle.allCases where style != .custom {
            #expect(!style.requiresCustomInstructions)
        }
    }

    @Test("Custom style folds the user's own instructions into its instruction")
    func customStyleUsesUserInstructions() {
        let instruction = WritingStyle.custom.instruction(customInstructions: "Always answer like a pirate.")
        #expect(instruction.contains("Always answer like a pirate."))
    }

    @Test("Custom style falls back to its base instruction when nothing was written")
    func customStyleWithoutInstructionsFallsBack() {
        let instruction = WritingStyle.custom.instruction(customInstructions: "   ")
        #expect(instruction == WritingStyle.custom.baseInstruction)
    }

    @Test("Presets ignore custom instructions")
    func presetsIgnoreCustomInstructions() {
        let instruction = WritingStyle.professional.instruction(customInstructions: "Answer like a pirate.")
        #expect(instruction == WritingStyle.professional.baseInstruction)
    }

    @Test("Developer instruction protects technical identifiers")
    func developerInstructionMentionsIdentifiers() {
        let instruction = WritingStyle.developer.baseInstruction
        #expect(instruction.contains("API names"))
        #expect(instruction.contains("ticket IDs"))
        #expect(instruction.contains("Never invent technical details."))
    }

    @Test("The default style is Professional")
    func defaultIsProfessional() {
        #expect(WritingStyle.default == .professional)
    }
}
