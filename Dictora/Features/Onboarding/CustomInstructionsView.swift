import SwiftUI

/// Collects the user's own instructions.
///
/// Two separate fields on purpose: the Custom style needs its own definition,
/// while "additional instructions" layer on top of *any* style — including the
/// presets — which is how the two combine later at prompt-build time.
struct CustomInstructionsView: View {
    let style: WritingStyle
    @Binding var customInstructions: String
    @Binding var additionalInstructions: String
    let onContinue: () -> Void
    let onBack: () -> Void

    private static let additionalPlaceholder = """
    Keep my messages concise and friendly. Preserve technical terms and ticket IDs. \
    Don't add information I didn't say.
    """

    private static let customPlaceholder = """
    Rewrite my dictation as short, direct sentences suitable for a team chat.
    """

    private var isCustomInstructionsSatisfied: Bool {
        guard style.requiresCustomInstructions else { return true }
        return !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        OnboardingScaffold(
            icon: .symbol("text.append"),
            title: "Additional instructions",
            message: "Tell Dictora anything it should always do with your dictation. This applies on top of your writing style."
        ) {
            VStack(alignment: .leading, spacing: 24) {
                if style.requiresCustomInstructions {
                    InstructionField(
                        title: "Your custom style",
                        subtitle: "Required, because you chose the Custom writing style.",
                        placeholder: Self.customPlaceholder,
                        text: $customInstructions
                    )
                }

                InstructionField(
                    title: "Additional instructions",
                    subtitle: "Optional. Applies to every writing style.",
                    placeholder: Self.additionalPlaceholder,
                    text: $additionalInstructions
                )
            }
        } footer: {
            VStack(spacing: 10) {
                OnboardingPrimaryButton(
                    title: "Continue",
                    isEnabled: isCustomInstructionsSatisfied,
                    action: onContinue
                )
                if !isCustomInstructionsSatisfied {
                    Text("Add your custom instructions to continue.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Back", action: onBack)
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct InstructionField: View {
    let title: String
    let subtitle: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(10)
                .dictoraCard()
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(title)
        }
    }
}

#Preview {
    @Previewable @State var custom = ""
    @Previewable @State var additional = ""
    CustomInstructionsView(
        style: .custom,
        customInstructions: $custom,
        additionalInstructions: $additional,
        onContinue: {},
        onBack: {}
    )
    .frame(width: 520, height: 720)
}
