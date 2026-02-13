import SwiftUI

/// Warp-inspired interactive sidebar row with smooth hover/selection state transitions.
/// Provides consistent interaction patterns across all sidebar views.
///
/// States: normal → hovered → selected (mutually exclusive visual treatments)
/// Transitions: 100ms linear (matching Warp's responsive feel)
struct SidebarRow<Leading: View, Trailing: View>: View {
    let isSelected: Bool
    var depth: Int = 0
    let onTap: () -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.adaptiveTheme) private var theme
    @State private var isHovered = false

    private let indentWidth: CGFloat = 16
    private let maxIndentLevels: CGFloat = 6

    private var indentOffset: CGFloat {
        min(CGFloat(depth), maxIndentLevels) * indentWidth
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AdaptiveTheme.spacing6) {
                if depth > 0 {
                    Spacer()
                        .frame(width: indentOffset)
                }

                leading()

                Spacer(minLength: 0)

                trailing()
            }
            .padding(.vertical, AdaptiveTheme.spacing6)
            .padding(.horizontal, AdaptiveTheme.spacing10)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.linear(duration: AdaptiveTheme.animationFast), value: isHovered)
        .animation(.linear(duration: AdaptiveTheme.animationFast), value: isSelected)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            theme.selectionActiveC
        } else if isHovered {
            theme.surfaceHoverC
        } else {
            Color.clear
        }
    }
}

// MARK: - Convenience Initializers

extension SidebarRow where Trailing == EmptyView {
    /// Row with leading content only (no trailing)
    init(
        isSelected: Bool,
        depth: Int = 0,
        onTap: @escaping () -> Void,
        @ViewBuilder leading: @escaping () -> Leading
    ) {
        self.isSelected = isSelected
        self.depth = depth
        self.onTap = onTap
        self.leading = leading
        self.trailing = { EmptyView() }
    }
}

/// Convenience: icon + label row (most common sidebar pattern)
struct SidebarIconRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var depth: Int = 0
    var iconColor: Color? = nil
    let onTap: () -> Void

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        SidebarRow(isSelected: isSelected, depth: depth, onTap: onTap) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor ?? theme.textSecondaryC)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13))
                .foregroundColor(theme.textPrimaryC)
                .lineLimit(1)
        }
    }
}

/// Convenience: file tree row with expand chevron
struct SidebarFileRow: View {
    let name: String
    let isDirectory: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let depth: Int
    let onTap: () -> Void
    var onChevronTap: (() -> Void)? = nil

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        SidebarRow(isSelected: isSelected, depth: depth, onTap: onTap) {
            // Chevron for directories
            if isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.textMutedC)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .onTapGesture { onChevronTap?() ?? onTap() }
            } else {
                Spacer().frame(width: 16)
            }

            // File/folder icon
            Image(systemName: isDirectory ? "folder.fill" : "doc.text.fill")
                .font(.system(size: 14))
                .foregroundColor(isDirectory ? theme.folderIconC : theme.markdownIconC)
                .frame(width: 20)

            // Name
            Text(name)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(name.hasPrefix(".") ? theme.textMutedC : theme.textPrimaryC)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
