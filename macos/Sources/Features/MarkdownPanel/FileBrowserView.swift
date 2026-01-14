import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - Keyboard Direction Enum

enum KeyboardDirection {
    case up
    case down
}

/// A Warp-inspired file browser sidebar for selecting markdown files
struct FileBrowserView: View {
    @Binding var rootPath: String
    let onFileSelected: (String) -> Void

    @State private var items: [FileItem] = []
    @State private var expandedDirs: Set<String> = []
    @State private var selectedPath: String?
    @State private var errorMessage: String?
    @AppStorage("ghostty.fileBrowserShowHidden") private var showHiddenFiles: Bool = false
    @State private var loadGeneration: Int = 0  // Prevents race conditions
    @AppStorage("ghostty.fileBrowserSearchText") private var searchText: String = ""
    @State private var selectedItemIndex: Int = -1  // For keyboard navigation
    @State private var recentFiles: [String] = []  // Persisted across sessions via UserDefaults
    @AppStorage("ghostty.fileBrowserShowQuickAccess") private var showQuickAccess: Bool = true  // Persisted toggle state for unified accordion
    @State private var isDropTargetHighlighted = false  // For drag-and-drop visual feedback

    /// Effective path - terminal's CWD or fallback to home directory
    private var effectivePath: String {
        rootPath.isEmpty ? NSHomeDirectory() : rootPath
    }

    private var projectName: String {
        return URL(fileURLWithPath: effectivePath).lastPathComponent
    }
    
    /// Breadcrumb components from current path
    private var breadcrumbComponents: [(name: String, path: String)] {
        let url = URL(fileURLWithPath: effectivePath)
        var components: [(String, String)] = [("Home", NSHomeDirectory())]
        
        guard effectivePath != NSHomeDirectory() else { return components }
        
        let pathComponents = url.pathComponents
        var currentPath = ""
        
        for component in pathComponents where component != "/" {
            currentPath = (currentPath as NSString).appendingPathComponent(component)
            components.append((component, currentPath))
        }
        
        return components
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
            
            // Compact toolbar
            FileBrowserToolbar(
                showHiddenFiles: $showHiddenFiles,
                onGoUp: goUp,
                onOpenFinder: openInFinder,
                canGoUp: canGoUp
            )
            .onChange(of: showHiddenFiles) { _ in loadDirectory() }
            
            SectionDivider()
            
            // Breadcrumb navigation
            BreadcrumbBar(components: breadcrumbComponents, onNavigate: { path in
                rootPath = path
            })
            
            SectionDivider()
            
            // MARK: - Quick Access Section (Unified Accordion)
            
            DisclosureGroup(isExpanded: $showQuickAccess) {
                VStack(alignment: .leading, spacing: PanelTheme.spacing8) {
                    // Search field
                    VStack(alignment: .leading, spacing: PanelTheme.spacing4) {
                        Text("Filter")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(PanelTheme.textMuted))
                            .tracking(0.5)
                            .padding(.horizontal, PanelTheme.spacing10)
                        
                        HStack(spacing: PanelTheme.spacing8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundColor(Color(PanelTheme.textMuted))
                            
                            TextField("Filter files...", text: $searchText)
                                .font(.system(size: 12))
                                .textFieldStyle(.plain)
                            
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(PanelTheme.textMuted))
                                }
                                .buttonStyle(.plain)
                                .help("Clear search")
                            }
                        }
                        .padding(.horizontal, PanelTheme.spacing10)
                        .padding(.vertical, PanelTheme.spacing8)
                        .background(Color(PanelTheme.surfaceElevated))
                        .overlay(
                            RoundedRectangle(cornerRadius: PanelTheme.radiusSmall, style: .continuous)
                                .stroke(Color(PanelTheme.borderSubtle), lineWidth: 1)
                        )
                    }
                    
                    // Recent files (shown only if available)
                    if !recentFiles.isEmpty {
                        VStack(alignment: .leading, spacing: PanelTheme.spacing4) {
                            Text("Recent")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color(PanelTheme.textMuted))
                                .tracking(0.5)
                                .padding(.horizontal, PanelTheme.spacing10)
                            
                            VStack(alignment: .leading, spacing: PanelTheme.spacing4) {
                                ForEach(Array(recentFiles.prefix(5).enumerated()), id: \.element) { _, filePath in
                                    RecentFileButton(
                                        filePath: filePath,
                                        onSelect: {
                                            selectedPath = filePath
                                            addToRecentFiles(filePath)
                                            onFileSelected(filePath)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, PanelTheme.spacing10)
                        }
                    }
                }
                .padding(.vertical, PanelTheme.spacing8)
            } label: {
                HStack(spacing: PanelTheme.spacing6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(PanelTheme.textMuted))
                    
                    Text("Quick Access")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(PanelTheme.textMuted))
                    
                    Spacer()
                }
            }
            .padding(.horizontal, PanelTheme.spacing8)
            .padding(.vertical, PanelTheme.spacing6)
            .animation(.easeInOut(duration: PanelTheme.animationNormal), value: showQuickAccess)

            SectionDivider()

            // MARK: - Contents Section

            // Project header
            ProjectHeader(name: projectName)

            Capsule()
                .fill(Color(PanelTheme.border))
                .frame(height: 1)
                .padding(.horizontal, PanelTheme.spacing8)

            // File tree
            if let error = errorMessage {
                EmptyStateView(message: error)
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
                                            addToRecentFiles(path)
                                            onFileSelected(path)
                                        },
                                        showHiddenFiles: showHiddenFiles
                                    )
                                    .id(index)
                                    .onReceive(Just(selectedItemIndex)) { newIndex in
                                        if newIndex >= 0 && newIndex < filteredItems.count {
                                            withAnimation(.spring(response: PanelTheme.springResponse, dampingFraction: PanelTheme.springDamping)) {
                                                proxy.scrollTo(newIndex, anchor: .center)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, PanelTheme.spacing6)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous)
                        .fill(Color(PanelTheme.background))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous)
                        .stroke(
                            isDropTargetHighlighted
                                ? Color(PanelTheme.selectionActive)
                                : Color(PanelTheme.borderSubtle),
                            lineWidth: isDropTargetHighlighted ? 2 : 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous))
                .padding(.horizontal, PanelTheme.spacing8)
                .padding(.vertical, PanelTheme.spacing8)
                .onDrop(of: [.fileURL], isTargeted: $isDropTargetHighlighted) { providers in
                    handleFileDrop(providers: providers)
                }
            }
            
            // Keyboard navigation hint
            if !filteredItems.isEmpty {
                Text("↑↓ to navigate • ⏎/Space to select • ⎋ to clear")
                    .font(.caption2)
                    .foregroundColor(Color(PanelTheme.textMuted))
                    .padding(.horizontal, PanelTheme.spacing12)
                    .padding(.vertical, PanelTheme.spacing4)
            }
        }
        .frame(minWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: PanelTheme.radiusLarge, style: .continuous)
                .fill(Color(PanelTheme.background))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PanelTheme.radiusLarge, style: .continuous)
                .stroke(Color(PanelTheme.borderSubtle), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusLarge, style: .continuous))
        .onAppear { 
            loadDirectory()
            loadRecentFilesFromStorage()
        }
        .onChange(of: rootPath) { _ in
            // Clear stale state when directory changes
            expandedDirs.removeAll()
            selectedPath = nil
            loadDirectory()
        }
        .onChange(of: recentFiles) { _ in
            saveRecentFilesToStorage()
        }
        .onChange(of: showQuickAccess) { _ in
            // showQuickAccess is already persisted via @AppStorage
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
            addToRecentFiles(item.path)
            onFileSelected(item.path)
        }

        return .handled
    }
    
    /// Add file to recent files (persisted, max 10 entries)
    private func addToRecentFiles(_ filePath: String) {
        // Remove if already exists, then insert at beginning
        recentFiles.removeAll { $0 == filePath }
        recentFiles.insert(filePath, at: 0)
        
        // Keep max 10 recent files
        if recentFiles.count > 10 {
            recentFiles = Array(recentFiles.prefix(10))
        }
    }

    /// Save recent files to UserDefaults
    private func saveRecentFilesToStorage() {
        let defaults = UserDefaults.standard
        defaults.set(recentFiles, forKey: "ghostty.fileBrowserRecentFiles")
    }

    /// Load recent files from UserDefaults
    private func loadRecentFilesFromStorage() {
        let defaults = UserDefaults.standard
        if let savedFiles = defaults.array(forKey: "ghostty.fileBrowserRecentFiles") as? [String] {
            recentFiles = savedFiles
        }
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
                        addToRecentFiles(url.path)
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

// MARK: - Section Divider

struct SectionDivider: View {
    var body: some View {
        Capsule()
            .fill(Color(PanelTheme.borderSubtle))
            .frame(height: 1)
            .padding(.vertical, PanelTheme.spacing6)
            .padding(.horizontal, PanelTheme.spacing8)
    }
}

// MARK: - Toolbar

struct FileBrowserToolbar: View {
    @Binding var showHiddenFiles: Bool
    let onGoUp: () -> Void
    let onOpenFinder: () -> Void
    let canGoUp: Bool

    var body: some View {
        HStack(spacing: PanelTheme.spacing8) {
            ToolbarIconButton(
                icon: "arrow.up",
                tooltip: "Parent directory",
                action: onGoUp
            )
            .disabled(!canGoUp)
            .opacity(canGoUp ? 1 : 0.4)

            ToolbarIconButton(
                icon: showHiddenFiles ? "eye.fill" : "eye.slash.fill",
                tooltip: showHiddenFiles ? "Hide hidden files" : "Show hidden files",
                action: { showHiddenFiles.toggle() }
            )

            Spacer()

            ToolbarIconButton(
                icon: "folder",
                tooltip: "Reveal in Finder",
                action: onOpenFinder
            )
        }
        .padding(.horizontal, PanelTheme.spacing12)
        .padding(.vertical, PanelTheme.spacing8)
        .background(
            RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous)
                .fill(Color(PanelTheme.surfaceElevated))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous)
                .stroke(Color(PanelTheme.borderSubtle), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous))
    }
}

struct ToolbarIconButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(isHovered ? PanelTheme.iconHover : PanelTheme.iconDefault))
                .frame(width: 24, height: 24)
                .background(isHovered ? Color(PanelTheme.surfaceHover) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusSmall, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: PanelTheme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Breadcrumb Bar

struct BreadcrumbBar: View {
    let components: [(name: String, path: String)]
    let onNavigate: (String) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PanelTheme.spacing4) {
                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    HStack(spacing: PanelTheme.spacing4) {
                        Button(action: { onNavigate(component.path) }) {
                            Text(component.name)
                                .font(.system(size: 11))
                                .foregroundColor(Color(PanelTheme.textMuted))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        
                        if index < components.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color(PanelTheme.textMuted))
                        }
                    }
                }
            }
            .padding(.horizontal, PanelTheme.spacing10)
            .padding(.vertical, PanelTheme.spacing6)
        }
        .background(Color(PanelTheme.surfaceElevated).opacity(0.5))
    }
}

// MARK: - Recent File Button

struct RecentFileButton: View {
    let filePath: String
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    private var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
    
    private var parentPath: String {
        URL(fileURLWithPath: filePath).deletingLastPathComponent().path
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: PanelTheme.spacing6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(PanelTheme.markdownIcon))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(.system(size: 11))
                        .foregroundColor(Color(PanelTheme.textPrimary))
                        .lineLimit(1)
                    
                    Text(parentPath)
                        .font(.system(size: 9))
                        .foregroundColor(Color(PanelTheme.textMuted))
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, PanelTheme.spacing8)
            .padding(.vertical, PanelTheme.spacing6)
            .background(isHovered ? Color(PanelTheme.surfaceHover) : Color.clear)
            .cornerRadius(PanelTheme.radiusSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Project Header

struct ProjectHeader: View {
    let name: String

    var body: some View {
        HStack(spacing: PanelTheme.spacing8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(PanelTheme.folderIcon))

            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(PanelTheme.textPrimary))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, PanelTheme.spacing12)
        .padding(.vertical, PanelTheme.spacing10)
        .background(
            RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous)
                .fill(Color(PanelTheme.surfaceElevated))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous)
                .stroke(Color(PanelTheme.borderSubtle), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous))
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: PanelTheme.spacing12) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 32))
                .foregroundColor(Color(PanelTheme.textMuted))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Color(PanelTheme.textSecondary))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PanelTheme.spacing12)
        .background(
            RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous)
                .fill(Color(PanelTheme.surfaceElevated))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous)
                .stroke(Color(PanelTheme.borderSubtle), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusMedium, style: .continuous))
        .padding(PanelTheme.spacing8)
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

    @State private var isHovered = false
    @State private var children: [FileItem]?

    private let indentWidth: CGFloat = 16
    private let maxIndentLevels: CGFloat = 6

    private var indentOffset: CGFloat {
        min(CGFloat(depth), maxIndentLevels) * indentWidth + PanelTheme.spacing8
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
                        .foregroundColor(Color(PanelTheme.textMuted))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleExpand() }
                } else {
                    Spacer().frame(width: 16)
                }

                // Icon
                Image(systemName: item.isDirectory ? "folder.fill" : "doc.text.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(item.isDirectory ? PanelTheme.folderIcon : PanelTheme.markdownIcon))
                    .frame(width: 20)

                // File name
                Text(item.name)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(item.name.hasPrefix(".") ? PanelTheme.textMuted : PanelTheme.textPrimary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, PanelTheme.spacing6)

                Spacer()
            }
            .padding(.vertical, PanelTheme.spacing4)
            .padding(.trailing, PanelTheme.spacing8)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusSmall, style: .continuous))
            .padding(.horizontal, PanelTheme.spacing4)
            .contentShape(RoundedRectangle(cornerRadius: PanelTheme.radiusSmall, style: .continuous))
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
        .animation(.easeOut(duration: PanelTheme.animationFast), value: isExpanded)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color(PanelTheme.selectionActive)
        } else if isHovered {
            Color(PanelTheme.surfaceHover)
        } else {
            Color.clear
        }
    }

    private func toggleExpand() {
        guard item.isDirectory else { return }

        if expandedDirs.contains(item.path) {
            expandedDirs.remove(item.path)
            // Release memory when collapsed
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

        // Move file I/O to background queue
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let processedItems = try FileItemProcessor.processDirectory(at: itemPath, showHidden: showHidden)
                DispatchQueue.main.async {
                    self.children = processedItems
                }
            } catch {
                DispatchQueue.main.async {
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
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    static func isMarkdownFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return markdownExtensions.contains(ext)
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

                if isDir.boolValue {
                    return FileItem(name: name, path: fullPath, isDirectory: true)
                } else if isMarkdownFile(name) {
                    return FileItem(name: name, path: fullPath, isDirectory: false)
                }
                return nil
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
}
