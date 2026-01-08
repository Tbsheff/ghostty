import SwiftUI
import AppKit

// MARK: - Vibrancy Background

/// NSVisualEffectView wrapper for native macOS vibrancy
struct VibrancyBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .headerView
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Native Markdown Header

/// A native macOS-style header for the markdown panel with vibrancy effect
struct NativeMarkdownHeader: View {
    let filePath: String?
    let isLiveReloading: Bool
    @Binding var isSearchVisible: Bool
    @Binding var searchQuery: String
    @Binding var showOutline: Bool
    var isSearchFocused: FocusState<Bool>.Binding
    let onClose: () -> Void
    let onRefresh: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var closeHovered = false
    @State private var refreshHovered = false
    @State private var searchHovered = false
    @State private var outlineHovered = false

    private var theme: MarkdownTheme {
        MarkdownTheme(colorScheme: colorScheme)
    }

    private var breadcrumbs: [String] {
        guard let path = filePath else { return ["Preview"] }
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents.suffix(2)
        return components.filter { $0 != "/" }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Leading: File icon + breadcrumbs
            leadingContent

            Spacer(minLength: 12)

            // Trailing: Live indicator + actions
            trailingContent
        }
        .frame(height: 38)
        .padding(.horizontal, 12)
        .background(VibrancyBackground(material: .headerView))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.border.opacity(0.3))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        HStack(spacing: 6) {
            // Document icon
            Image(systemName: "doc.richtext")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.accent)

            // Breadcrumb path
            HStack(spacing: 4) {
                ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(theme.textMuted)
                    }

                    Text(component)
                        .font(.system(size: 12, weight: index == breadcrumbs.count - 1 ? .medium : .regular))
                        .foregroundColor(index == breadcrumbs.count - 1 ? theme.textPrimary : theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        HStack(spacing: 12) {
            // Search field (shown when visible)
            if isSearchVisible {
                searchField
            }

            // Live reload indicator
            if isLiveReloading && !isSearchVisible {
                liveIndicator
            }

            // Action buttons
            HStack(spacing: 2) {
                HeaderButton(
                    icon: "list.bullet.indent",
                    tooltip: "Toggle Outline",
                    isHovered: $outlineHovered,
                    theme: theme,
                    isActive: showOutline,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showOutline.toggle()
                        }
                    }
                )

                HeaderButton(
                    icon: "magnifyingglass",
                    tooltip: "Search (/)",
                    isHovered: $searchHovered,
                    theme: theme,
                    isActive: isSearchVisible,
                    action: {
                        isSearchVisible.toggle()
                        if isSearchVisible {
                            isSearchFocused.wrappedValue = true
                        } else {
                            searchQuery = ""
                        }
                    }
                )

                HeaderButton(
                    icon: "arrow.clockwise",
                    tooltip: "Refresh (⌘R)",
                    isHovered: $refreshHovered,
                    theme: theme,
                    action: onRefresh
                )

                HeaderButton(
                    icon: "xmark",
                    tooltip: "Close (Esc)",
                    isHovered: $closeHovered,
                    theme: theme,
                    action: onClose
                )
            }
        }
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 6) {
            TextField("Search...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(theme.textPrimary)
                .focused(isSearchFocused)
                .onSubmit {
                    // Keep search open on submit
                }
                .onExitCommand {
                    isSearchVisible = false
                    searchQuery = ""
                }

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.codeBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.border.opacity(0.5), lineWidth: 1)
                )
        )
        .frame(width: 160)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9, anchor: .trailing).combined(with: .opacity),
            removal: .scale(scale: 0.9, anchor: .trailing).combined(with: .opacity)
        ))
    }

    @ViewBuilder
    private var liveIndicator: some View {
        HStack(spacing: 5) {
            // Use a simple static indicator instead of infinite animation
            // to prevent CPU usage when panel is open but not actively changing
            Circle()
                .fill(theme.success)
                .frame(width: 6, height: 6)

            Text("Live")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(theme.success.opacity(0.12))
        )
    }
}

// MARK: - Header Button

struct HeaderButton: View {
    let icon: String
    let tooltip: String
    @Binding var isHovered: Bool
    let theme: MarkdownTheme
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? theme.accent : (isHovered ? theme.textPrimary : theme.textSecondary))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? theme.accent.opacity(0.15) : (isHovered ? theme.surfaceElevated : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Complete Native Panel View

/// Complete native markdown panel with header and content
struct NativeMarkdownPanelView: View {
    @Binding var content: String
    let filePath: String?
    let onClose: () -> Void
    let onRefresh: () -> Void
    var onExecuteCode: ((String) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    // Search state
    @State private var searchQuery = ""
    @State private var isSearchVisible = false
    @FocusState private var isSearchFocused: Bool

    // Outline sidebar state
    @State private var showOutline = false
    @State private var scrollTarget: Int?

    // Cache parsed blocks for both sidebar and content
    @State private var cachedBlocks: [MarkdownBlock] = []
    @State private var lastContent: String = ""

    private var theme: MarkdownTheme {
        MarkdownTheme(colorScheme: colorScheme)
    }

    /// Check if file is being watched for live reload
    private var isLiveReloading: Bool {
        filePath != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            NativeMarkdownHeader(
                filePath: filePath,
                isLiveReloading: isLiveReloading,
                isSearchVisible: $isSearchVisible,
                searchQuery: $searchQuery,
                showOutline: $showOutline,
                isSearchFocused: $isSearchFocused,
                onClose: onClose,
                onRefresh: onRefresh
            )

            if content.isEmpty {
                emptyState
            } else {
                // Get base directory from filePath for resolving relative image paths
                let basePath = filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
                NativeMarkdownView(
                    blocks: cachedBlocks,
                    scrollTarget: $scrollTarget,
                    onExecuteCode: onExecuteCode,
                    onClose: onClose,
                    basePath: basePath
                )
                .environment(\.searchQuery, searchQuery)
            }
        }
        .background(theme.background)
        .onChange(of: content) { newContent in
            parseContentIfNeeded(newContent)
        }
        .onAppear {
            parseContentIfNeeded(content)
        }
    }

    private func parseContentIfNeeded(_ newContent: String) {
        guard newContent != lastContent else { return }
        lastContent = newContent
        cachedBlocks = MarkdownParser.parse(newContent)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(theme.textMuted.opacity(0.5))

            VStack(spacing: 6) {
                Text("No markdown file selected")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.textPrimary)

                Text("Open a .md file to see the preview")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }
}
