import SwiftUI

/// Table of contents sidebar showing document headings for navigation
struct OutlineSidebar: View {
    let blocks: [MarkdownBlock]
    @Binding var scrollTarget: Int?

    @Environment(\.adaptiveTheme) private var theme

    /// Extract headings with their block indices for scroll targeting
    private var headings: [(index: Int, level: Int, text: String)] {
        blocks.enumerated().compactMap { index, block in
            guard case .heading(let level, let content) = block else { return nil }
            return (index, level, content.plainText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("OUTLINE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.textMutedC)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, AdaptiveTheme.spacing12)
            .padding(.vertical, AdaptiveTheme.spacing8)

            SidebarDivider()

            if headings.isEmpty {
                SidebarEmptyState(icon: "list.bullet", message: "No headings")
            } else {
                // Heading list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(headings, id: \.index) { heading in
                            OutlineRow(
                                heading: heading,
                                onTap: {
                                    scrollTarget = heading.index
                                }
                            )
                        }
                    }
                    .padding(.vertical, AdaptiveTheme.spacing8)
                }
            }
        }
        .frame(width: 200)
        .background(theme.backgroundC)
    }
}

// MARK: - Outline Row

struct OutlineRow: View {
    let heading: (index: Int, level: Int, text: String)
    let onTap: () -> Void

    @Environment(\.adaptiveTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            Text(heading.text)
                .font(.system(size: 12))
                .foregroundColor(isHovered ? theme.accentC : theme.textPrimaryC)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AdaptiveTheme.spacing4)
                .padding(.leading, CGFloat(heading.level - 1) * 12 + 12)
                .padding(.trailing, AdaptiveTheme.spacing12)
        }
        .buttonStyle(.plain)
        .background(isHovered ? theme.surfaceHoverC : Color.clear)
        .onHover { isHovered = $0 }
        .animation(.linear(duration: AdaptiveTheme.animationFast), value: isHovered)
    }
}
