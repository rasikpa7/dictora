import Foundation
import Testing

#if os(macOS)
@testable import DictoraMac
#else
@testable import DictoraiOS
#endif

/// Returns a fixed string so tests assert on the rewriter's behaviour rather
/// than on any particular model's output.
private struct StubTextProcessor: TextProcessorProtocol {
    let kind: TextProcessorKind = .localFallback
    let output: String

    func availability() async -> TextProcessorAvailability { .available }
    func process(_ request: TextProcessingRequest) async throws -> String { output }
}

@Suite("Clipboard rewriting", .serialized)
@MainActor
struct ClipboardRewriterTests {
    private func makeRewriter(returning output: String) -> ClipboardRewriter {
        let processor = StubTextProcessor(output: output)
        return ClipboardRewriter(
            textProcessing: TextProcessingService(primary: processor, fallback: processor)
        )
    }

    /// Waits for the in-flight rewrite rather than sleeping a fixed amount.
    private func settle(_ rewriter: ClipboardRewriter) async {
        while rewriter.state.isWorking {
            await Task.yield()
        }
    }

    @Test("An empty clipboard is reported, not silently ignored")
    func emptyClipboardFails() async {
        Clipboard.copy("   \n  ")
        let rewriter = makeRewriter(returning: "unused")

        rewriter.rewriteClipboard(
            style: .professional,
            strength: .default,
            customInstructions: "",
            additionalInstructions: ""
        )

        #expect(rewriter.state.rewrite == nil)
        #expect(rewriter.state.errorMessage != nil)
    }

    @Test("The custom style refuses to run without instructions")
    func customStyleNeedsInstructions() async {
        Clipboard.copy("some text worth rewriting")
        let rewriter = makeRewriter(returning: "unused")

        rewriter.rewriteClipboard(
            style: .custom,
            strength: .default,
            customInstructions: "   ",
            additionalInstructions: ""
        )

        #expect(rewriter.state.errorMessage != nil)
    }

    @Test("A rewrite keeps both versions, so the user can compare them")
    func rewriteKeepsOriginal() async {
        Clipboard.copy("hey can you send me that file")
        let rewriter = makeRewriter(returning: "Could you send me that file?")

        rewriter.rewriteClipboard(
            style: .professional,
            strength: .default,
            customInstructions: "",
            additionalInstructions: ""
        )
        await settle(rewriter)

        let rewrite = try? #require(rewriter.state.rewrite)
        #expect(rewrite?.original == "hey can you send me that file")
        #expect(rewrite?.rewritten == "Could you send me that file?")
        #expect(rewrite?.style == .professional)
        #expect(rewrite?.isUnchanged == false)
    }

    @Test("Text the model leaves alone is flagged as unchanged")
    func unchangedRewriteIsDetected() async {
        Clipboard.copy("Already perfectly clear.")
        let rewriter = makeRewriter(returning: "Already perfectly clear.")

        rewriter.rewriteClipboard(
            style: .grammarOnly,
            strength: .default,
            customInstructions: "",
            additionalInstructions: ""
        )
        await settle(rewriter)

        #expect(rewriter.state.rewrite?.isUnchanged == true)
    }

    @Test("Copying the result puts the rewritten text on the clipboard")
    func copyingResultReplacesClipboard() async {
        Clipboard.copy("make this nicer")
        let rewriter = makeRewriter(returning: "Please make this nicer.")

        rewriter.rewriteClipboard(
            style: .professional,
            strength: .default,
            customInstructions: "",
            additionalInstructions: ""
        )
        await settle(rewriter)
        rewriter.copyResultToClipboard()

        #expect(Clipboard.currentString() == "Please make this nicer.")
        #expect(rewriter.hasCopiedResult)
    }

    @Test("Resetting clears the result and the copied flag")
    func resetClearsState() async {
        Clipboard.copy("something")
        let rewriter = makeRewriter(returning: "Something.")

        rewriter.rewriteClipboard(
            style: .professional,
            strength: .default,
            customInstructions: "",
            additionalInstructions: ""
        )
        await settle(rewriter)
        rewriter.copyResultToClipboard()
        rewriter.reset()

        #expect(rewriter.state == .idle)
        #expect(!rewriter.hasCopiedResult)
    }
}
