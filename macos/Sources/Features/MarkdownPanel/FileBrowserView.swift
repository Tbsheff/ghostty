import SwiftUI
import UniformTypeIdentifiers

/// A Warp-inspired file browser sidebar for selecting markdown files
struct FileBrowserView: View {
    @Binding var rootPath: String
    let onFileSelected: (String) -> Void

    @State private var items: [FileItem] = []
    @State private var expandedDirs: Set<String> = []
    @State private var selectedPath: String?
    @State private var errorMessage: String?
    @State private var showHiddenFiles: Bool = false
    @State private var loadGeneration: Int = 0  // Prevents race conditions

    /// Effective path - terminal's CWD or fallback to home directory
    private var effectivePath: String {
        rootPath.isEmpty ? NSHomeDirectory() : rootPath
    }

    private var projectName: String {
        return URL(fileURLWithPath: effectivePath).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact toolbar
            FileBrowserToolbar(
                showHiddenFiles: $showHiddenFiles,
                onGoUp: goUp,
                onOpenFinder: openInFinder,
                canGoUp: canGoUp
            )
            .onChange(of: showHiddenFiles) { _ in loadDirectory() }

            // Project header
            ProjectHeader(name: projectName)

            Rectangle()
                .fill(Color(PanelTheme.border))
                .frame(height: 1)

            // File tree
            if let error = errorMessage {
                EmptyStateView(message: error)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            FileTreeRow(
                                item: item,
                                depth: 0,
                                isExpanded: expandedDirs.contains(item.path),
                                isSelected: selectedPath == item.path,
                                expandedDirs: $expandedDirs,
                                selectedPath: $selectedPath,
                                onFileSelected: onFileSelected,
                                showHiddenFiles: showHiddenFiles
                            )
                        }
                    }
                    .padding(.vertical, PanelTheme.spacing6)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 200)
        .background(Color(PanelTheme.background))
        .onAppear { loadDirectory() }
        .onChange(of: rootPath) { _ in
            // Clear stale state when directory changes
            expandedDirs.removeAll()
            selectedPath = nil
            loadDirectory()
        }
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
        .background(Color(PanelTheme.surfaceElevated))
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
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
        .background(Color(PanelTheme.surfaceElevated))
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
        .padding()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row content
            HStack(spacing: 0) {
                // Indentation
                Spacer()
                    .frame(width: CGFloat(depth) * indentWidth + PanelTheme.spacing8)

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
            .clipShape(RoundedRectangle(cornerRadius: PanelTheme.radiusSmall))
            .padding(.horizontal, PanelTheme.spacing4)
            .contentShape(Rectangle())
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
