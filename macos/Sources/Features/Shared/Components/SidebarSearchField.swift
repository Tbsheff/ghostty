import SwiftUI

/// Warp-inspired themed search field with clear button and focus indicator.
/// Provides consistent search UI across all sidebar views.
struct SidebarSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var label: String? = nil

    @Environment(\.adaptiveTheme) private var theme
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AdaptiveTheme.spacing4) {
            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.textMutedC)
                    .tracking(0.5)
                    .textCase(.uppercase)
            }

            HStack(spacing: AdaptiveTheme.spacing8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textMutedC)

                TextField(placeholder, text: $text)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .focused($isFocused)

                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(theme.textMutedC)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, AdaptiveTheme.spacing10)
            .padding(.vertical, AdaptiveTheme.spacing8)
            .background(theme.surfaceElevatedC)
            .overlay(
                RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous)
                    .stroke(
                        isFocused ? theme.accentC.opacity(0.6) : theme.borderSubtleC,
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous))
            .animation(.linear(duration: AdaptiveTheme.animationFast), value: isFocused)
            .animation(.linear(duration: AdaptiveTheme.animationFast), value: text.isEmpty)
        }
    }
}

// MARK: - Empty State

/// Theme-aware empty state view for sidebars
struct SidebarEmptyState: View {
    let icon: String
    let message: String
    var detail: String? = nil

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        VStack(spacing: AdaptiveTheme.spacing12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(theme.textMutedC)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondaryC)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(theme.textMutedC)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AdaptiveTheme.spacing12)
    }
}
