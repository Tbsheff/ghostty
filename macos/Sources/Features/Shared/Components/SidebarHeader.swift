import SwiftUI

/// Action button definition for sidebar headers
struct HeaderAction: Identifiable {
    let id = UUID()
    let icon: String
    let tooltip: String
    let action: () -> Void
    var isEnabled: Bool = true
}

/// Warp-inspired collapsible section header with smooth chevron animation
/// and optional action buttons on the trailing edge.
struct SidebarHeader: View {
    let title: String
    var icon: String? = nil
    @Binding var isExpanded: Bool
    var actions: [HeaderAction] = []

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: AdaptiveTheme.springResponse, dampingFraction: AdaptiveTheme.springDamping)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: AdaptiveTheme.spacing6) {
                // Chevron with rotation animation
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.textMutedC)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.textMutedC)
                }

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.textMutedC)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                // Action buttons
                if isExpanded {
                    ForEach(actions) { action in
                        SidebarHeaderButton(action: action)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, AdaptiveTheme.spacing10)
            .padding(.vertical, AdaptiveTheme.spacing8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Small icon button for sidebar header actions
private struct SidebarHeaderButton: View {
    let action: HeaderAction

    @Environment(\.adaptiveTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action.action) {
            Image(systemName: action.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(isHovered ? theme.iconHover : theme.iconDefault))
                .frame(width: 22, height: 22)
                .background(isHovered ? theme.surfaceHoverC : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(action.tooltip)
        .disabled(!action.isEnabled)
        .opacity(action.isEnabled ? 1 : 0.4)
        .onHover { isHovered = $0 }
        .animation(.linear(duration: AdaptiveTheme.animationFast), value: isHovered)
    }
}

// MARK: - Section Divider

/// Theme-aware section divider for sidebar sections
struct SidebarDivider: View {
    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        Capsule()
            .fill(theme.borderSubtleC)
            .frame(height: 1)
            .padding(.vertical, AdaptiveTheme.spacing6)
            .padding(.horizontal, AdaptiveTheme.spacing8)
    }
}

// MARK: - Project Header

/// Sidebar project/folder header with icon and title
struct SidebarProjectHeader: View {
    let name: String
    var icon: String = "folder.fill"

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        HStack(spacing: AdaptiveTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(theme.folderIconC)

            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textPrimaryC)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, AdaptiveTheme.spacing12)
        .padding(.vertical, AdaptiveTheme.spacing10)
        .background(
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                .fill(theme.surfaceElevatedC)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                .stroke(theme.borderSubtleC, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous))
    }
}
