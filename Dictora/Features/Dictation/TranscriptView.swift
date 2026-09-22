import SwiftUI

/// A labelled block of transcript text, optionally copyable.
///
/// Used for both the raw transcript and the polished result so the two are
/// visually comparable at a glance.
struct TranscriptView: View {
    let title: String
    let text: String
    var symbolName: String?
    var isEmphasised: Bool = false
    var allowsCopy: Bool = false

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)

                Spacer(minLength: 8)

                if allowsCopy {
                    Button {
                        Clipboard.copy(text)
                        withAnimation(.smooth(duration: 0.2)) { didCopy = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.smooth(duration: 0.2)) { didCopy = false }
                        }
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(text.isEmpty)
                }
            }
            .foregroundStyle(.secondary)

            Text(text)
                .font(isEmphasised ? .title3 : .body)
                .foregroundStyle(isEmphasised ? .primary : .secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dictoraCard()
    }
}

#Preview {
    VStack(spacing: 12) {
        TranscriptView(
            title: "You said",
            text: "hey naveen i fixed that issue you can check latest build",
            symbolName: "waveform"
        )
        TranscriptView(
            title: "Dictora",
            text: "Hey Naveen, I've fixed the issue. You can check it in the latest build.",
            symbolName: "sparkles",
            isEmphasised: true,
            allowsCopy: true
        )
    }
    .padding()
    .frame(width: 420)
}
