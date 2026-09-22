#if os(macOS)
import SwiftUI

/// The floating "Listening… / Processing… / Done" pill.
///
/// Kept as a plain SwiftUI view with no dependencies so it can be previewed and
/// restyled independently of the window plumbing in ``DictationOverlayController``.
struct DictationOverlayView: View {
    let state: DictationState
    var transcriptPreview: String = ""

    var body: some View {
        HStack(spacing: 12) {
            indicator
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.statusText)
                    .font(.headline)
                if !transcriptPreview.isEmpty {
                    Text(transcriptPreview)
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
        .frame(width: 260, alignment: .leading)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule().strokeBorder(.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .animation(.smooth(duration: 0.2), value: state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.statusText)
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
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
        DictationOverlayView(state: .listening, transcriptPreview: "hey naveen i fixed that issue")
        DictationOverlayView(state: .processing)
        DictationOverlayView(state: .completed)
    }
    .padding(40)
}
#endif
