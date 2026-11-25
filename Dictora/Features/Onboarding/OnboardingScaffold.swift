import SwiftUI

/// What an onboarding screen shows above its title.
///
/// A closed set rather than a generic view builder: only two things ever belong
/// here, and this keeps the scaffold's generic signature to content and footer.
enum OnboardingIcon {
    /// Dictora's own mark. Reserved for the welcome screen.
    case appLogo
    case symbol(String)
}

/// Common chrome for every onboarding screen: icon, title, body, scrolling
/// content and a pinned footer. Individual steps supply only what differs.
struct OnboardingScaffold<Content: View, Footer: View>: View {
    let icon: OnboardingIcon
    let title: String
    let message: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        switch icon {
                        case .appLogo:
                            AppLogo(size: 64)
                        case .symbol(let symbolName):
                            Image(systemName: symbolName)
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }

                        Text(title)
                            .font(.largeTitle.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(message)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)

                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 12) {
                Divider()
                footer
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Primary call-to-action shared by every onboarding footer.
struct OnboardingPrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}
