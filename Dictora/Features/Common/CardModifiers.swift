import SwiftUI

/// Shared surface treatment for Dictora's cards.
///
/// Semantic materials and colours only, so light/dark mode and accessibility
/// contrast settings are handled by the system rather than by hard-coded values.
private struct DictoraCard: ViewModifier {
    var isSelected: Bool
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.background.secondary, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
    }
}

extension View {
    func dictoraCard(isSelected: Bool = false, cornerRadius: CGFloat = 14) -> some View {
        modifier(DictoraCard(isSelected: isSelected, cornerRadius: cornerRadius))
    }
}
