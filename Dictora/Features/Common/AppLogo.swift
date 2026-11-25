import SwiftUI

/// Dictora's mark, drawn from the same artwork as the app icon.
///
/// Use this wherever the app identifies itself — onboarding, window headers.
/// Everywhere else keeps using SF Symbols, which adapt to the surrounding text
/// style in a way a raster logo cannot.
struct AppLogo: View {
    /// Edge length in points. The asset carries enough resolution for anything
    /// up to 128pt without upscaling.
    var size: CGFloat = 32

    /// Ratio Apple uses for the iOS icon mask, so the logo reads as an app icon
    /// at any size.
    private static let cornerRadiusRatio: CGFloat = 0.2237

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * Self.cornerRadiusRatio, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(alignment: .bottom, spacing: 20) {
        AppLogo(size: 28)
        AppLogo(size: 48)
        AppLogo(size: 72)
    }
    .padding(40)
}
