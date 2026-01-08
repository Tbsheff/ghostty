import SwiftUI

/// Table of contents sidebar showing document headings for navigation
struct OutlineSidebar: View {
    let blocks: [MarkdownBlock]
    @Binding var scrollTarget: Int?
    let theme: MarkdownTheme

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
                    .foregroundColor(theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .background(theme.border)

            if headings.isEmpty {
                // Empty state
                VStack {
                    Spacer()
                    Text("No headings")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textMuted)
                    Spacer()
                }
            } else {
                // Heading list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(headings, id: \.index) { heading in
                            OutlineRow(
                                heading: heading,
                                theme: theme,
                                onTap: {
                                    scrollTarget = heading.index
                                }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 200)
        .background(theme.codeBackground)
    }
}

// MARK: - Outline Row

struct OutlineRow: View {
    let heading: (index: Int, level: Int, text: String)
    let theme: MarkdownTheme
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            Text(heading.text)
                .font(.system(size: 12))
                .foregroundColor(isHovered ? theme.accent : theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.leading, CGFloat(heading.level - 1) * 12 + 12)
                .padding(.trailing, 12)
        }
        .buttonStyle(.plain)
        .background(isHovered ? theme.surfaceElevated : Color.clear)
        .onHover { isHovered = $0 }
    }
}
