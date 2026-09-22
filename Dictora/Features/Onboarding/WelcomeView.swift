import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(
            symbolName: "waveform",
            title: "Welcome to Dictora",
            message: "Speak naturally. Dictora turns your speech into clear, polished text."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    symbolName: "mic",
                    title: "Dictate anywhere in the app",
                    detail: "Tap once and start talking."
                )
                FeatureRow(
                    symbolName: "wand.and.sparkles",
                    title: "Polished automatically",
                    detail: "Your transcript is rewritten in the style you choose."
                )
                FeatureRow(
                    symbolName: "lock",
                    title: "Runs on your device",
                    detail: "Speech and rewriting use Apple's on-device frameworks."
                )
            }
        } footer: {
            OnboardingPrimaryButton(title: "Get Started", action: onContinue)
        }
    }
}

private struct FeatureRow: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbolName)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView(onContinue: {})
        .frame(width: 520, height: 620)
}
