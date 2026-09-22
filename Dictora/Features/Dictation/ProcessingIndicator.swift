import SwiftUI

/// Compact status line shown beneath the dictation button and inside the macOS
/// floating overlay, so both surfaces describe progress identically.
struct ProcessingIndicator: View {
    let state: DictationState

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .listening:
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            case .requestingPermission, .transcribing, .processing:
                ProgressView()
                    .controlSize(.small)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            case .idle:
                Image(systemName: "mic")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Text(state.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .animation(.smooth(duration: 0.2), value: state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.statusText)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ProcessingIndicator(state: .idle)
        ProcessingIndicator(state: .listening)
        ProcessingIndicator(state: .processing)
        ProcessingIndicator(state: .completed)
        ProcessingIndicator(state: .failed(.nothingHeard))
    }
    .padding()
}
