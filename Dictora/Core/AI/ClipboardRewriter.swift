import Foundation
import Observation
import OSLog

/// Rewrites text the user already has — whatever is on the clipboard — in a
/// style and strength they pick at the moment of rewriting.
///
/// Deliberately separate from `DictationManager`: this shares the same text
/// processing pipeline but none of the audio, permission or state machinery,
/// and the two must not be able to interfere with each other.
@MainActor
@Observable
final class ClipboardRewriter {
    struct Rewrite: Equatable, Sendable {
        let original: String
        let rewritten: String
        let style: WritingStyle
        let strength: TransformationStrength
        let processor: TextProcessorKind

        /// True when the model returned the text unchanged, which is a useful
        /// thing to say rather than showing two identical boxes.
        var isUnchanged: Bool {
            original.trimmingCharacters(in: .whitespacesAndNewlines)
                == rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    enum State: Equatable {
        case idle
        case working
        case finished(Rewrite)
        case failed(String)

        var isWorking: Bool { self == .working }
        var rewrite: Rewrite? {
            if case .finished(let rewrite) = self { return rewrite }
            return nil
        }
        var errorMessage: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    private(set) var state: State = .idle
    /// Set once the user copies the result back, so the UI can confirm it.
    private(set) var hasCopiedResult = false

    private let textProcessing: TextProcessingService
    private let logger = Logger(subsystem: DictoraLog.subsystem, category: "ClipboardRewrite")

    /// Guards against a slow rewrite overwriting a newer one's result.
    private var activeTask: Task<Void, Never>?

    init(textProcessing: TextProcessingService) {
        self.textProcessing = textProcessing
    }

    /// Text currently on the clipboard, or nil when there is nothing to rewrite.
    var clipboardPreview: String? {
        guard let text = Clipboard.currentString() else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func reset() {
        activeTask?.cancel()
        activeTask = nil
        state = .idle
        hasCopiedResult = false
    }

    func rewriteClipboard(
        style: WritingStyle,
        strength: TransformationStrength,
        customInstructions: String,
        additionalInstructions: String
    ) {
        guard let original = clipboardPreview else {
            state = .failed("There's no text on your clipboard. Copy something first.")
            return
        }
        if style.requiresCustomInstructions,
           customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .failed("Add your custom instructions in Settings before using the Custom style.")
            return
        }

        activeTask?.cancel()
        hasCopiedResult = false
        state = .working

        activeTask = Task { [weak self] in
            guard let self else { return }
            let request = TextProcessingRequest(
                transcript: original,
                style: style,
                customInstructions: customInstructions,
                additionalInstructions: additionalInstructions,
                strength: strength
            )

            do {
                let processed = try await textProcessing.process(request)
                guard !Task.isCancelled else { return }
                state = .finished(
                    Rewrite(
                        original: original,
                        rewritten: processed.text,
                        style: style,
                        strength: strength,
                        processor: processed.processor
                    )
                )
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Clipboard rewrite failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription)
            }
            activeTask = nil
        }
    }

    /// Puts the rewritten text back on the clipboard, ready to paste.
    func copyResultToClipboard() {
        guard let rewrite = state.rewrite else { return }
        Clipboard.copy(rewrite.rewritten)
        hasCopiedResult = true
    }
}
