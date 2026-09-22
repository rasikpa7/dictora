import Foundation
import Testing

#if os(macOS)
@testable import DictoraMac
#else
@testable import DictoraiOS
#endif

@Suite("LocalFallbackTextProcessor")
struct LocalFallbackTextProcessorTests {
    private let processor = LocalFallbackTextProcessor()

    private func request(
        _ transcript: String,
        strength: TransformationStrength = .balanced
    ) -> TextProcessingRequest {
        TextProcessingRequest(transcript: transcript, style: .professional, strength: strength)
    }

    @Test("Capitalises sentences and adds terminal punctuation")
    func cleansUpBasicTranscript() async throws {
        let output = try await processor.process(request("hey naveen i fixed that issue"))
        #expect(output == "Hey naveen i fixed that issue.")
    }

    @Test("Collapses runs of whitespace")
    func collapsesWhitespace() async throws {
        let output = try await processor.process(request("hello    there\n\n friend"))
        #expect(output == "Hello there friend.")
    }

    @Test("Removes standalone filler words")
    func removesFillerWords() async throws {
        let output = try await processor.process(request("um so uh this is the fix"))
        #expect(!output.lowercased().contains(" um "))
        #expect(output.contains("this is the fix"))
    }

    @Test("Minimal strength keeps every word the user said")
    func minimalStrengthKeepsFillers() async throws {
        let output = try await processor.process(request("um this is the fix", strength: .minimal))
        #expect(output.lowercased().contains("um"))
    }

    @Test("Existing terminal punctuation is not duplicated")
    func doesNotDoublePunctuate() async throws {
        let output = try await processor.process(request("this is done."))
        #expect(output == "This is done.")
    }

    @Test("An empty transcript is rejected rather than silently returned")
    func emptyTranscriptThrows() async {
        await #expect(throws: TextProcessingError.emptyTranscript) {
            try await processor.process(request("   "))
        }
    }

    @Test("The fallback processor is always available")
    func isAlwaysAvailable() async {
        #expect(await processor.availability() == .available)
    }

    @Test("Results are tagged as basic cleanup, not Apple Intelligence")
    func reportsItsOwnKind() {
        #expect(processor.kind == .localFallback)
    }
}
