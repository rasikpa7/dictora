import SwiftUI

struct WritingStyleSetupView: View {
    @Binding var selection: WritingStyle
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            symbolName: "text.badge.checkmark",
            title: "How should Dictora handle your dictation?",
            message: "Pick a starting point. You can change this at any time in Settings."
        ) {
            VStack(spacing: 12) {
                ForEach(WritingStyle.allCases) { style in
                    WritingStyleCard(style: style, isSelected: style == selection) {
                        selection = style
                    }
                }
            }
        } footer: {
            VStack(spacing: 10) {
                OnboardingPrimaryButton(title: "Continue", action: onContinue)
                Button("Back", action: onBack)
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    @Previewable @State var selection: WritingStyle = .professional
    WritingStyleSetupView(selection: $selection, onContinue: {}, onBack: {})
        .frame(width: 520, height: 720)
}
