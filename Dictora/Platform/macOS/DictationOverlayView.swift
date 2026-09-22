#if os(macOS)
import SwiftUI

/// Everything the floating overlay displays, as one value.
///
/// Passing a snapshot rather than loose parameters means the controller can
/// diff presentations and skip redundant window updates.
struct OverlayPresentation: Equatable, Sendable {
    var state: DictationState
    var transcriptPreview: String
    /// Set after a shortcut-triggered dictation is delivered, e.g. "Inserted".
    var footnote: String?

    init(state: DictationState, transcriptPreview: String = "", footnote: String? = nil) {
        self.state = state
        self.transcriptPreview = transcriptPreview
        self.footnote = footnote
    }
}

/// The floating "Listening… / Processing… / Done" pill.
///
/// Kept as a plain SwiftUI view with no dependencies so it can be previewed and
/// restyled independently of the window plumbing in ``DictationOverlayController``.
struct DictationOverlayView: View {
    let presentation: OverlayPresentation

    private var secondaryLine: String? {
        if let footnote = presentation.footnote, !footnote.isEmpty { return footnote }
        let preview = presentation.transcriptPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? nil : preview
    }

    var body: some View {
        HStack(spacing: 12) {
            indicator
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.state.statusText)
                    .font(.headline)
                if let secondaryLine {
                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 280, alignment: .leading)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule().strokeBorder(.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .animation(.smooth(duration: 0.2), value: presentation)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(secondaryLine.map { "\(presentation.state.statusText). \($0)" }
            ?? presentation.state.statusText)
    }

    @ViewBuilder
    private var indicator: some View {
        switch presentation.state {
        case .listening:
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        case .requestingPermission, .transcribing, .processing:
            ProgressView().controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
        case .idle:
            Image(systemName: "mic")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        DictationOverlayView(
            presentation: OverlayPresentation(
                state: .listening,
                transcriptPreview: "hey naveen i fixed that issue"
            )
        )
        DictationOverlayView(presentation: OverlayPresentation(state: .processing))
        DictationOverlayView(
            presentation: OverlayPresentation(state: .completed, footnote: "Inserted")
        )
        DictationOverlayView(
            presentation: OverlayPresentation(state: .failed(.nothingHeard))
        )
    }
    .padding(40)
}
#endif
