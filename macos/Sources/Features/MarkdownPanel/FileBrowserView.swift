import SwiftUI
import UniformTypeIdentifiers

// MARK: - Keyboard Direction Enum

enum KeyboardDirection {
    case up
    case down
}

/// A Warp-inspired file browser sidebar for selecting markdown files
struct FileBrowserView: View {
    @Binding var rootPath: String
    let onFileSelected: (String) -> Void

    @Environment(\.adaptiveTheme) private var theme
    @State private var items: [FileItem] = []
    @State private var expandedDirs: Set<String> = []
    @State private var selectedPath: String?
    @State private var errorMessage: String?
    @AppStorage("ghostty.fileBrowserShowHidden") private var showHiddenFiles: Bool = false
    @State private var loadGeneration: Int = 0  // Prevents race conditions
    @State private var searchText: String = ""
    @State private var selectedItemIndex: Int = -1  // For keyboard navigation
    @State private var isDropTargetHighlighted = false  // For drag-and-drop visual feedback

    /// Effective path - terminal's CWD or fallback to home directory
    private var effectivePath: String {
        rootPath.isEmpty ? NSHomeDirectory() : rootPath
    }

    private var projectName: String {
        return URL(fileURLWithPath: effectivePath).lastPathComponent
    }

    /// Filtered items based on search text
    private var filteredItems: [FileItem] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Navigation Section

            // Compact header: project name + toolbar actions in one row
            HStack(spacing: AdaptiveTheme.spacing6) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(theme.textMutedC)

                Text(projectName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.textPrimaryC)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                ToolbarIconButton(
                    icon: "arrow.up",
                    tooltip: "Parent directory",
                    action: goUp
                )
                .disabled(!canGoUp)
                .opacity(canGoUp ? 1 : 0.4)

                ToolbarIconButton(
                    icon: showHiddenFiles ? "eye.fill" : "eye.slash.fill",
                    tooltip: showHiddenFiles ? "Hide hidden files" : "Show hidden files",
                    action: { showHiddenFiles.toggle() }
                )

                ToolbarIconButton(
                    icon: "folder",
                    tooltip: "Reveal in Finder",
                    action: openInFinder
                )
            }
            .padding(.horizontal, AdaptiveTheme.spacing12)
            .padding(.vertical, AdaptiveTheme.spacing8)
            .onChange(of: showHiddenFiles) { _ in loadDirectory() }

            SidebarDivider()

            // Search field
            SidebarSearchField(text: $searchText, placeholder: "Filter files...", label: "Filter")
                .padding(.horizontal, AdaptiveTheme.spacing8)
                .padding(.vertical, AdaptiveTheme.spacing6)

            // File tree
            if let error = errorMessage {
                SidebarEmptyState(icon: "folder.badge.questionmark", message: error)
            } else {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                    FileTreeRow(
                                        item: item,
                                        depth: 0,
                                        isExpanded: expandedDirs.contains(item.path),
                                        isSelected: selectedPath == item.path,
                                        expandedDirs: $expandedDirs,
                                        selectedPath: $selectedPath,
                                        onFileSelected: { path in
                                            selectedPath = path
                                            onFileSelected(path)
                                        },
                                        showHiddenFiles: showHiddenFiles
                                    )
                                    .id(index)
                                }
                            }
                            .padding(.vertical, AdaptiveTheme.spacing6)
                        }
                        .scrollContentBackground(.hidden)
                        .onChange(of: selectedItemIndex) { newIndex in
                            if newIndex >= 0 && newIndex < filteredItems.count {
                                withAnimation(.spring(response: AdaptiveTheme.springResponse, dampingFraction: AdaptiveTheme.springDamping)) {
                                    proxy.scrollTo(newIndex, anchor: .center)
                                }
                            }
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                        .fill(theme.backgroundC)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous)
                        .stroke(
                            isDropTargetHighlighted
                                ? theme.selectionActiveC
                                : theme.borderSubtleC,
                            lineWidth: isDropTargetHighlighted ? 2 : 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium, style: .continuous))
                .padding(.horizontal, AdaptiveTheme.spacing8)
                .padding(.vertical, AdaptiveTheme.spacing8)
                .onDrop(of: [.fileURL], isTargeted: $isDropTargetHighlighted) { providers in
                    handleFileDrop(providers: providers)
                }
            }

            // Keyboard navigation hint
            if !filteredItems.isEmpty {
                Text("↑↓ to navigate • ⏎/Space to select • ⎋ to clear")
                    .font(.caption2)
                    .foregroundColor(theme.textMutedC)
                    .padding(.horizontal, AdaptiveTheme.spacing12)
                    .padding(.vertical, AdaptiveTheme.spacing4)
            }
        }
        .frame(minWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusLarge, style: .continuous)
                .fill(theme.backgroundC)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusLarge, style: .continuous)
                .stroke(theme.borderSubtleC, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusLarge, style: .continuous))
        .onAppear {
            loadDirectory()
        }
        .onChange(of: rootPath) { _ in
            // Clear stale state when directory changes
            expandedDirs.removeAll()
            selectedPath = nil
            loadDirectory()
        }
        .backport.onKeyPress(.upArrow) { _ in handleKeyboardNavigation(direction: .up) }
        .backport.onKeyPress(.downArrow) { _ in handleKeyboardNavigation(direction: .down) }
        .backport.onKeyPress(.return) { _ in handleKeyboardSelect() }
        .backport.onKeyPress(.space) { _ in handleKeyboardSelect() }
        .backport.onKeyPress(.escape) { _ in handleKeyboardEscape() }
    }

    private var canGoUp: Bool {
        return effectivePath != "/" && effectivePath != NSHomeDirectory()
    }

    private func goUp() {
        let parent = (effectivePath as NSString).deletingLastPathComponent
        rootPath = parent
    }

    private func openInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: effectivePath)
    }

    // MARK: - Keyboard Navigation

    private func handleKeyboardNavigation(direction: KeyboardDirection) -> BackportKeyPressResult {
        guard !filteredItems.isEmpty else { return .ignored }

        if direction == .up {
            if selectedItemIndex > 0 {
                selectedItemIndex -= 1
            } else if selectedItemIndex == -1 {
                selectedItemIndex = filteredItems.count - 1
            }
        } else if direction == .down {
            if selectedItemIndex < filteredItems.count - 1 {
                selectedItemIndex += 1
            } else if selectedItemIndex == -1 {
                selectedItemIndex = 0
            }
        }

        // Sync visual selection with keyboard position
        if selectedItemIndex >= 0 && selectedItemIndex < filteredItems.count {
            selectedPath = filteredItems[selectedItemIndex].path
        }

        return .handled
    }

    private func handleKeyboardSelect() -> BackportKeyPressResult {
        guard selectedItemIndex >= 0, selectedItemIndex < filteredItems.count else {
            return .ignored
        }

        let item = filteredItems[selectedItemIndex]

        if item.isDirectory {
            // Toggle expansion for directories
            if expandedDirs.contains(item.path) {
                expandedDirs.remove(item.path)
            } else {
                expandedDirs.insert(item.path)
            }
        } else {
            // Select file
            selectedPath = item.path
            onFileSelected(item.path)
        }

        return .handled
    }

    private func handleKeyboardEscape() -> BackportKeyPressResult {
        // Clear selection on Escape
        selectedItemIndex = -1
        selectedPath = nil
        return .handled
    }

    // MARK: - Drag and Drop

    /// Handle files dropped from Finder
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false

        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }

                DispatchQueue.main.async {
                    if url.hasDirectoryPath {
                        rootPath = url.path
                        return
                    }

                    let fileName = url.lastPathComponent
                    if FileItemProcessor.isMarkdownFile(fileName) {
                        selectedPath = url.path
                        onFileSelected(url.path)
                    }
                }
            }
        }

        return accepted
    }

    /// Load directory contents on background queue to prevent UI blocking
    private func loadDirectory() {
        let path = effectivePath
        let showHidden = showHiddenFiles

        // Increment generation to invalidate any in-flight loads
        loadGeneration += 1
        let currentGeneration = loadGeneration

        // Move file I/O to background queue
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let processedItems = try FileItemProcessor.processDirectory(at: path, showHidden: showHidden)

                // Update UI on main queue only if this is still the current generation
                DispatchQueue.main.async {
                    guard self.loadGeneration == currentGeneration else { return }
                    self.items = processedItems
                    self.errorMessage = nil
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.loadGeneration == currentGeneration else { return }
                    self.errorMessage = "Could not read directory"
                    self.items = []
                }
            }
        }
    }
}

struct ToolbarIconButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @Environment(\.adaptiveTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(isHovered ? theme.iconHover : theme.iconDefault))
                .frame(width: 24, height: 24)
                .background(isHovered ? theme.surfaceHoverC : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
        .animation(.linear(duration: AdaptiveTheme.animationFast), value: isHovered)
    }
}

// MARK: - File Tree Row (Recursive)

struct FileTreeRow: View {
    let item: FileItem
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    @Binding var expandedDirs: Set<String>
    @Binding var selectedPath: String?
    let onFileSelected: (String) -> Void
    let showHiddenFiles: Bool

    @Environment(\.adaptiveTheme) private var theme
    @State private var isHovered = false
    @State private var children: [FileItem]?
    @State private var loadGeneration: Int = 0

    private let indentWidth: CGFloat = 16
    private let maxIndentLevels: CGFloat = 6

    private var indentOffset: CGFloat {
        min(CGFloat(depth), maxIndentLevels) * indentWidth + AdaptiveTheme.spacing8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row content
            HStack(spacing: 0) {
                // Indentation
                Spacer()
                    .frame(width: indentOffset)

                // Chevron for directories
                if item.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textMutedC)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleExpand() }
                } else {
                    Spacer().frame(width: 16)
                }

                // Icon
                Image(systemName: item.isDirectory ? "folder" : "doc.text")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(theme.textMutedC)
                    .frame(width: 20)

                // File name
                Text(item.name)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(item.name.hasPrefix(".") ? theme.textMutedC : theme.textPrimaryC)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, AdaptiveTheme.spacing6)

                Spacer()
            }
            .padding(.vertical, AdaptiveTheme.spacing4)
            .padding(.trailing, AdaptiveTheme.spacing8)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous))
            .padding(.horizontal, AdaptiveTheme.spacing4)
            .contentShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous))
            .onTapGesture {
                if item.isDirectory {
                    toggleExpand()
                } else {
                    selectedPath = item.path
                    onFileSelected(item.path)
                }
            }
            .onHover { isHovered = $0 }

            // Children (expanded directories)
            if item.isDirectory && isExpanded, let children = children {
                ForEach(children) { child in
                    FileTreeRow(
                        item: child,
                        depth: depth + 1,
                        isExpanded: expandedDirs.contains(child.path),
                        isSelected: selectedPath == child.path,
                        expandedDirs: $expandedDirs,
                        selectedPath: $selectedPath,
                        onFileSelected: onFileSelected,
                        showHiddenFiles: showHiddenFiles
                    )
                }
            }
        }
        .animation(.easeOut(duration: AdaptiveTheme.animationFast), value: isExpanded)
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

    private func toggleExpand() {
        guard item.isDirectory else { return }

        if expandedDirs.contains(item.path) {
            expandedDirs.remove(item.path)
            // Increment generation to invalidate any in-flight loads
            loadGeneration += 1
            children = nil
        } else {
            expandedDirs.insert(item.path)
            loadChildren()
        }
    }

    /// Load children on background queue
    private func loadChildren() {
        guard children == nil else { return }

        let itemPath = item.path
        let showHidden = showHiddenFiles
        loadGeneration += 1
        let currentGeneration = loadGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let processedItems = try FileItemProcessor.processDirectory(at: itemPath, showHidden: showHidden)
                DispatchQueue.main.async {
                    guard self.loadGeneration == currentGeneration else { return }
                    self.children = processedItems
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.loadGeneration == currentGeneration else { return }
                    self.children = []
                }
            }
        }
    }
}

// MARK: - FileItem

struct FileItem: Identifiable, Hashable {
    // Use path as stable ID - prevents SwiftUI from treating items as "new" on every reload
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
}

// MARK: - Shared File Processing

/// Centralized file processing to avoid code duplication
enum FileItemProcessor {
    static func isMarkdownFile(_ name: String) -> Bool {
        MarkdownFileDetector.isMarkdownFile(name)
    }

    /// Process directory contents into sorted FileItems (call from background queue)
    static func processDirectory(at path: String, showHidden: Bool) throws -> [FileItem] {
        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        return contents
            .filter { showHidden || !$0.hasPrefix(".") }
            .compactMap { name -> FileItem? in
                let fullPath = (path as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) else {
                    return nil
                }

                return FileItem(name: name, path: fullPath, isDirectory: isDir.boolValue)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}

#Preview {
    FileBrowserView(
        rootPath: .constant(NSHomeDirectory()),
        onFileSelected: { _ in }
    )
    .frame(width: 260, height: 500)
    .adaptiveThemeFromSystem()
}
