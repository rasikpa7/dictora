import SwiftUI

/// Rewrite whatever is on the clipboard in a style and tone chosen right here.
///
/// The style picked here is intentionally *not* the dictation default: the
/// point of this screen is trying a different tone on text you already have,
/// so changing it must not quietly change how dictation behaves.
struct RephraseView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var style: WritingStyle = .professional
    @State private var strength: TransformationStrength = .default
    /// The clipboard can change while the window is open, so it is re-read
    /// rather than captured once.
    @State private var clipboardPreview: String?

    private var rewriter: ClipboardRewriter { environment.clipboardRewriter }
    private var preferences: UserPreferences { environment.appState.preferences }

    private var canRephrase: Bool {
        clipboardPreview != nil && !rewriter.state.isWorking
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controls
                source
                result
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task {
            style = preferences.selectedWritingStyle
            strength = preferences.transformationStrength
            refreshClipboard()
        }
        .onChange(of: rewriter.state) { _, _ in refreshClipboard() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Style", selection: $style) {
                    ForEach(WritingStyle.allCases) { option in
                        Label(option.displayName, systemImage: option.symbolName).tag(option)
                    }
                }
                .frame(maxWidth: 260)

                Picker("Tone", selection: $strength) {
                    ForEach(TransformationStrength.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .frame(maxWidth: 220)
            }

            Text(style.shortDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Rephrase Clipboard", systemImage: "wand.and.sparkles") {
                    rewriter.rewriteClipboard(
                        style: style,
                        strength: strength,
                        customInstructions: preferences.customInstructions,
                        additionalInstructions: preferences.additionalInstructions
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRephrase)

                Button("Paste From Clipboard Again", systemImage: "arrow.clockwise") {
                    refreshClipboard()
                    rewriter.reset()
                }
                .labelStyle(.iconOnly)
                .help("Re-read the clipboard")

                if rewriter.state.isWorking {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var source: some View {
        if let clipboardPreview {
            RephrasePanel(
                title: "On your clipboard",
                symbolName: "doc.on.clipboard",
                text: clipboardPreview
            )
        } else {
            ContentUnavailableView(
                "Nothing to rephrase",
                systemImage: "doc.on.clipboard",
                description: Text("Copy some text in any app, then come back here.")
            )
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var result: some View {
        if let message = rewriter.state.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let rewrite = rewriter.state.rewrite {
            RephrasePanel(
                title: "\(rewrite.style.displayName) · \(rewrite.strength.displayName)",
                symbolName: "sparkles",
                text: rewrite.rewritten
            ) {
                Button(rewriter.hasCopiedResult ? "Copied" : "Copy",
                       systemImage: rewriter.hasCopiedResult ? "checkmark" : "doc.on.doc") {
                    rewriter.copyResultToClipboard()
                }
                .disabled(rewriter.hasCopiedResult)
            }

            if rewrite.isUnchanged {
                Text("\(rewrite.processor.displayName) left the text as it was — it already matches this style.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Rewritten by \(rewrite.processor.displayName).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refreshClipboard() {
        clipboardPreview = rewriter.clipboardPreview
    }
}

private struct RephrasePanel<Accessory: View>: View {
    let title: String
    let symbolName: String
    let text: String
    @ViewBuilder var accessory: Accessory

    init(
        title: String,
        symbolName: String,
        text: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.symbolName = symbolName
        self.text = text
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title.uppercased(), systemImage: symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                accessory
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 1)
        }
    }
}

#Preview {
    RephraseView()
        .environment(AppEnvironment.preview())
        .frame(width: 560, height: 700)
}
