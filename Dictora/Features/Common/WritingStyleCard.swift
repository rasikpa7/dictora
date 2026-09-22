import SwiftUI

/// A selectable writing-style card, shared by onboarding and settings so both
/// surfaces stay consistent as styles are added.
struct WritingStyleCard: View {
    let style: WritingStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: style.symbolName)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(style.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(style.shortDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .dictoraCard(isSelected: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    VStack(spacing: 12) {
        WritingStyleCard(style: .professional, isSelected: true) {}
        WritingStyleCard(style: .developer, isSelected: false) {}
    }
    .padding()
    .frame(width: 420)
}
