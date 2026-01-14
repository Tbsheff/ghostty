import SwiftUI
import AppKit
import GhosttyKit

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
    var config: Ghostty.Config? = nil  // Ghostty config for theme customization

    @Environment(\.colorScheme) private var colorScheme
    @State private var closeHovered = false
    @State private var refreshHovered = false
    @State private var searchHovered = false
    @State private var outlineHovered = false

    private var theme: MarkdownTheme {
        MarkdownTheme(colorScheme: colorScheme, config: config)
    }

    private var breadcrumbs: [String] {
        guard let path = filePath else { return ["Preview"] }
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents.suffix(2)
        return components.filter { $0 != "/" }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Leading: File icon + breadcrumbs + live indicator
            leadingContent

            Spacer(minLength: 12)

            // Trailing: Actions grouped together
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
        HStack(spacing: 8) {
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
            
            // Live reload indicator (repositioned near breadcrumbs)
            if isLiveReloading && !isSearchVisible {
                Divider()
                    .frame(height: 16)
                    .padding(.leading, 4)
                
                HStack(spacing: 5) {
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
    }

    @ViewBuilder
    private var trailingContent: some View {
        HStack(spacing: 12) {
            // Search field (shown when visible)
            if isSearchVisible {
                searchField
            }

            // Action buttons (grouped together on the right)
            HStack(spacing: 2) {
                HeaderButton(
                    icon: "list.bullet.indent",
                    tooltip: "Toggle Outline (⌘⇧O)",
                    isHovered: $outlineHovered,
                    theme: theme,
                    isActive: showOutline,
                    keyboardShortcut: KeyboardShortcut("o", modifiers: [.command, .shift]),
                    action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showOutline.toggle()
                        }
                    }
                )

                HeaderButton(
                    icon: "magnifyingglass",
                    tooltip: "Search (⌘F, /)",
                    isHovered: $searchHovered,
                    theme: theme,
                    isActive: isSearchVisible,
                    keyboardShortcut: KeyboardShortcut("f", modifiers: [.command]),
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
                    keyboardShortcut: KeyboardShortcut("r", modifiers: [.command]),
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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(theme.textMuted)

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
                .accessibilityLabel("Search markdown")
                .accessibilityHint("Type to search, press Escape to close")

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
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
                        .animation(.easeInOut(duration: 0.15), value: isSearchFocused.wrappedValue)
                )
        )
        .frame(width: 160)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
    }

}

// MARK: - Header Button

struct HeaderButton: View {
    let icon: String
    let tooltip: String
    @Binding var isHovered: Bool
    let theme: MarkdownTheme
    var isActive: Bool = false
    var keyboardShortcut: KeyboardShortcut? = nil
    let action: () -> Void

    @FocusState private var isFocused: Bool

    private var buttonContent: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? theme.accent : (isHovered || isFocused ? theme.textPrimary : theme.textSecondary))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? theme.accent.opacity(0.15) : (isHovered || isFocused ? theme.surfaceElevated : Color.clear))
                        .animation(.easeInOut(duration: 0.15), value: isHovered || isFocused)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
        .focused($isFocused)
        .accessibilityLabel(tooltip)
        .accessibilityHint("Press to activate")
    }

    @ViewBuilder
    var body: some View {
        if let keyboardShortcut {
            buttonContent.keyboardShortcut(keyboardShortcut)
        } else {
            buttonContent
        }
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
    var config: Ghostty.Config? = nil  // Ghostty config for theme customization

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
    @State private var isHTMLDocument = false

    private var theme: MarkdownTheme {
        MarkdownTheme(colorScheme: colorScheme, config: config)
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
                onRefresh: onRefresh,
                config: config
            )

            if content.isEmpty {
                emptyState
            } else {
                // Get base directory from filePath for resolving relative image paths
                let basePath = filePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
                if isHTMLDocument {
                    HTMLDocumentView(
                        html: content,
                        baseURL: basePath.map { URL(fileURLWithPath: $0, isDirectory: true) }
                    )
                } else {
                    NativeMarkdownView(
                        blocks: cachedBlocks,
                        scrollTarget: $scrollTarget,
                        onExecuteCode: onExecuteCode,
                        onClose: onClose,
                        basePath: basePath,
                        config: config
                    )
                    .environment(\.searchQuery, searchQuery)
                }
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
        let htmlDocument = MarkdownParser.looksLikeHTMLDocument(newContent)
        isHTMLDocument = htmlDocument
        if htmlDocument {
            cachedBlocks = []
        } else {
            cachedBlocks = MarkdownParser.parse(newContent)
        }
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
