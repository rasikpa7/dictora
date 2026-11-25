import SwiftUI

/// The dictation surface, shared by the iOS home screen and the macOS main window.
///
/// It reads state from ``DictationManager`` and sends it only three messages —
/// toggle, reset, request permissions — so all pipeline logic stays out of the view.
struct DictationView: View {
    @Environment(AppEnvironment.self) private var environment

    /// macOS embeds this in a window that already has its own chrome.
    var showsHeader: Bool = true

    private var dictation: DictationManager { environment.dictation }
    private var preferences: UserPreferences { environment.appState.preferences }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if showsHeader {
                    DictationHeader(style: preferences.selectedWritingStyle)
                }

                VStack(spacing: 14) {
                    DictationButton(state: dictation.state) {
                        Task { await dictation.toggle() }
                    }
                    ProcessingIndicator(state: dictation.state)
                }
                .padding(.vertical, 8)

                if let error = dictation.state.error {
                    DictationErrorBanner(error: error) {
                        dictation.reset()
                    }
                }

                if !dictation.transcript.isEmpty, dictation.result == nil {
                    TranscriptView(
                        title: dictation.state.isCapturing ? "Capturing" : "You said",
                        text: dictation.transcript.displayText,
                        symbolName: "waveform"
                    )
                }

                if let result = dictation.result {
                    ResultSection(result: result)
                }

                if dictation.state == .idle, dictation.result == nil, dictation.transcript.isEmpty {
                    EmptyStateHint()
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(.background)
    }
}

private struct DictationHeader: View {
    let style: WritingStyle

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                AppLogo(size: 32)
                Text("Dictora")
                    .font(.largeTitle.weight(.semibold))
            }

            Label(style.displayName, systemImage: style.symbolName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dictora. Writing style: \(style.displayName)")
    }
}

private struct ResultSection: View {
    let result: DictationResult

    var body: some View {
        VStack(spacing: 12) {
            TranscriptView(
                title: "You said",
                text: result.rawTranscript,
                symbolName: "waveform"
            )

            TranscriptView(
                title: "Dictora · \(result.style.displayName)",
                text: result.polishedText,
                symbolName: "sparkles",
                isEmphasised: true,
                allowsCopy: true
            )

            HStack(spacing: 6) {
                Image(systemName: { switch result.processor { case .claude: "sparkles"; case .foundationModel: "apple.intelligence"; case .localFallback: "textformat.abc" } }())
                    .accessibilityHidden(true)
                Text("Polished with \(result.processor.displayName)")
                ShareLink(item: result.polishedText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .labelStyle(.titleAndIcon)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DictationErrorBanner: View {
    let error: DictationError
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(error.errorDescription ?? "Something went wrong")
                    .font(.subheadline.weight(.semibold))
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dictoraCard()
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyStateHint: View {
    var body: some View {
        Text("Tap the microphone and start speaking.")
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}

#Preview {
    DictationView()
        .environment(AppEnvironment.preview())
        .frame(width: 480, height: 700)
}
