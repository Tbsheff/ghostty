import SwiftUI

// MARK: - Environment Key

/// Environment key for injecting AdaptiveTheme into view hierarchy.
/// Usage: `.adaptiveTheme(theme)` on parent view, then
/// `@Environment(\.adaptiveTheme) var theme` in child views.
struct AdaptiveThemeKey: EnvironmentKey {
    static let defaultValue: AdaptiveTheme = .system
}

extension EnvironmentValues {
    var adaptiveTheme: AdaptiveTheme {
        get { self[AdaptiveThemeKey.self] }
        set { self[AdaptiveThemeKey.self] = newValue }
    }
}

// MARK: - View Modifier

extension View {
    /// Inject an adaptive theme into this view's environment.
    /// All child views can access via `@Environment(\.adaptiveTheme)`.
    func adaptiveTheme(_ theme: AdaptiveTheme) -> some View {
        environment(\.adaptiveTheme, theme)
    }

    /// Convenience: create theme from color scheme and apply.
    /// Uses system appearance when no terminal background is available.
    func adaptiveThemeFromSystem() -> some View {
        modifier(SystemThemeModifier())
    }
}

/// Modifier that automatically derives theme from system color scheme
private struct SystemThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.adaptiveTheme, AdaptiveTheme(colorScheme: colorScheme))
    }
}
