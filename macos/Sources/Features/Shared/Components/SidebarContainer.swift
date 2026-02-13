import SwiftUI

/// Unified sidebar container with Warp-inspired rounded corners, borders, and subtle gradient.
/// Provides consistent visual wrapping for all sidebar content areas.
struct SidebarContainer<Content: View>: View {
    let identifier: String?
    let content: Content

    @Environment(\.adaptiveTheme) private var theme

    init(identifier: String? = nil, @ViewBuilder content: () -> Content) {
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusLarge, style: .continuous)
                .fill(theme.backgroundC)

            content
        }
        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusLarge, style: .continuous)
                .stroke(theme.borderSubtleC, lineWidth: 1)
        )
        .modifier(OptionalAccessibilityIdentifier(identifier: identifier))
    }
}

/// Applies accessibilityIdentifier only when non-nil
private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
