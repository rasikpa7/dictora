import SwiftUI

struct SetupCompleteView: View {
    let selectedStyle: WritingStyle
    let onFinish: () -> Void

    /// The closing promise differs because system-wide insertion is a macOS-only
    /// capability; iOS deliberately makes no such claim.
    private var platformMessage: String {
        #if os(macOS)
        "Next, you'll be able to use a shortcut to dictate from anywhere on your Mac."
        #else
        "Start speaking and Dictora will turn your speech into polished text."
        #endif
    }

    var body: some View {
        OnboardingScaffold(
            symbolName: "checkmark.seal",
            title: "Dictora is ready.",
            message: platformMessage
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SummaryRow(
                    symbolName: selectedStyle.symbolName,
                    title: "Writing style",
                    value: selectedStyle.displayName
                )
                SummaryRow(
                    symbolName: "gearshape",
                    title: "Change anything later",
                    value: "Settings"
                )
            }
        } footer: {
            OnboardingPrimaryButton(title: "Start using Dictora", action: onFinish)
        }
    }
}

private struct SummaryRow: View {
    let symbolName: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(title).font(.headline)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dictoraCard()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SetupCompleteView(selectedStyle: .professional, onFinish: {})
        .frame(width: 520, height: 620)
}
