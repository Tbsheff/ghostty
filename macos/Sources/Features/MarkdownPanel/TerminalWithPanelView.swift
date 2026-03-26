import SwiftUI
import Combine
import Darwin
import GhosttyKit

/// State management for the markdown panel and file browser
@MainActor
class MarkdownPanelState: ObservableObject {
    private static let fileBrowserVisibleKey = "ghostty.fileBrowserVisible"
    private static let markdownVisibleKey = "ghostty.markdownVisible"

    /// Whether the file browser (left panel) is visible
    @Published var fileBrowserVisible: Bool {
        didSet {
            UserDefaults.standard.set(fileBrowserVisible, forKey: Self.fileBrowserVisibleKey)
        }
    }

    /// Whether the markdown preview (right panel) is visible
    @Published var markdownVisible: Bool {
        didSet {
            UserDefaults.standard.set(markdownVisible, forKey: Self.markdownVisibleKey)
        }
    }

    /// When non-nil, markdown preview is shown as an overlay on the diff view.
    /// Transient — not persisted; always returns to diff on app restart.
    @Published var previewingFile: String?

    /// The currently displayed markdown content
    @Published var content: String = ""

    /// The path of the currently displayed file
    @Published var filePath: String?

    /// The root path for the file browser
    @Published var browserRootPath: String = ""

    /// Convenience: is any panel visible
    var isVisible: Bool {
        fileBrowserVisible || markdownVisible
    }

    /// File watcher for live reload
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    /// Debounce timer to batch rapid file changes
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.15  // 150ms debounce

    /// Generation counter to prevent stale Task completions from writing state
    private var loadGeneration: Int = 0

    init(fileBrowserDefaultHidden: Bool = false) {
        let defaults = UserDefaults.standard
        if fileBrowserDefaultHidden {
            // In workspace mode, the workspace sidebar replaces the file browser
            self.fileBrowserVisible = false
        } else {
            self.fileBrowserVisible = defaults.bool(forKey: Self.fileBrowserVisibleKey)
        }
        self.markdownVisible = defaults.bool(forKey: Self.markdownVisibleKey)
    }

    /// Load a markdown file asynchronously and show as overlay
    func loadFile(at path: String) {
        filePath = path
        previewingFile = path
        stopWatching()

        // Show panel immediately for responsiveness
        markdownVisible = true

        // Increment generation so any in-flight tasks become stale
        loadGeneration += 1
        let currentGeneration = loadGeneration

        // Read file on background queue to avoid blocking UI
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let fileContent = try String(contentsOfFile: path, encoding: .utf8)
                await MainActor.run {
                    guard let self, self.loadGeneration == currentGeneration else { return }
                    self.content = fileContent
                    self.startWatching(path: path)
                }
            } catch {
                await MainActor.run {
                    guard let self, self.loadGeneration == currentGeneration else { return }
                    self.content = "**Error:** Could not read file\n\n\(error.localizedDescription)"
                }
            }
        }
    }

    /// Refresh the current file
    func refresh() {
        guard let path = filePath else { return }
        loadFile(at: path)
    }

    /// Toggle both panels together
    func toggle() {
        let newState = !isVisible
        fileBrowserVisible = newState
        markdownVisible = newState
    }

    /// Toggle just the file browser
    func toggleFileBrowser() {
        fileBrowserVisible.toggle()
    }

    /// Toggle the right panel. Closing also dismisses any active preview.
    func toggleMarkdown() {
        if markdownVisible {
            previewingFile = nil
        }
        markdownVisible.toggle()
    }

    /// Dismiss the markdown preview overlay, returning to the diff view.
    /// Does not close the panel itself.
    func dismissPreview() {
        previewingFile = nil
        filePath = nil
        stopWatching()
    }

    /// Start watching a file for changes with debouncing
    private func startWatching(path: String) {
        // Stop any existing watcher first — guards against races where two
        // loadFile() calls dispatch background tasks that both reach here.
        stopWatching()

        // Convert Swift String to C string for the open() system call
        fileDescriptor = path.withCString { cPath in
            Darwin.open(cPath, O_EVTONLY)
        }
        guard fileDescriptor >= 0 else { return }

        // Capture fd value now - prevents race condition if stopWatching/startWatching
        // are called in rapid succession (old cancel handler would close wrong fd)
        let fd = fileDescriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            guard let self = self, self.fileWatcher != nil else { return }

            // Check if file was deleted or renamed
            let data = source.data
            if data.contains(.delete) || data.contains(.rename) {
                self.stopWatching()
                return
            }

            // Debounce rapid file changes (e.g., editors saving multiple times)
            self.debounceTimer?.invalidate()
            let timer = Timer(timeInterval: self.debounceInterval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.debounceTimer = timer
        }

        source.setCancelHandler {
            // Close the fd that was captured when this source was created
            close(fd)
        }

        source.resume()
        fileWatcher = source
    }

    /// Stop watching the current file
    private func stopWatching() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    deinit {
        debounceTimer?.invalidate()
        fileWatcher?.cancel()
    }

}

/// A view that wraps terminal content with optional file browser (left) and markdown panel (right).
/// Uses native NSSplitView for optimal drag performance - no SwiftUI re-renders during resize.
struct TerminalWithPanelView<Content: View>: View {
    /// The terminal content to display
    let content: Content

    /// Panel state
    @ObservedObject var panelState: MarkdownPanelState

    /// Ghostty config for theme customization
    var config: Ghostty.Config? = nil

    /// Width of the file browser (persisted via AppStorage)
    @AppStorage("ghostty.fileBrowserWidth") private var fileBrowserWidth: Double = 240

    /// Width of the markdown panel (persisted via AppStorage)
    @AppStorage("ghostty.markdownWidth") private var markdownWidth: Double = 300

    /// Minimum/maximum panel widths
    private let minPanelWidth: CGFloat = 160
    private let maxPanelWidth: CGFloat = 600

    /// State for code execution safety
    @State private var pendingCode: String?
    @State private var showDangerAlert = false

    /// Animation for panel transitions
    private let panelTransition = Animation.easeInOut(duration: AdaptiveTheme.animationNormal)

    init(panelState: MarkdownPanelState, config: Ghostty.Config? = nil, @ViewBuilder content: () -> Content) {
        self.panelState = panelState
        self.config = config
        self.content = content()
    }

    var body: some View {
        NativeSplitView(
            leftVisible: $panelState.fileBrowserVisible,
            rightVisible: $panelState.markdownVisible,
            leftWidth: Binding(
                get: { max(minPanelWidth, min(maxPanelWidth, CGFloat(fileBrowserWidth))) },
                set: { fileBrowserWidth = Double(max(minPanelWidth, min(maxPanelWidth, $0))) }
            ),
            rightWidth: Binding(
                get: { max(minPanelWidth, min(maxPanelWidth, CGFloat(markdownWidth))) },
                set: { markdownWidth = Double(max(minPanelWidth, min(maxPanelWidth, $0))) }
            ),
            left: {
                PanelContainer(identifier: "fileBrowser.panel") {
                    FileBrowserView(
                        rootPath: $panelState.browserRootPath,
                        onFileSelected: { path in
                            panelState.loadFile(at: path)
                        }
                    )
                }
            },
            center: {
                PanelContainer(identifier: "terminal.panel") {
                    content
                }
            },
            right: {
                PanelContainer(identifier: "rightPanel.panel") {
                    ZStack {
                        // Base layer: always the diff view
                        DiffPanelView(
                            cwd: panelState.browserRootPath,
                            onClose: {
                                withAnimation(panelTransition) {
                                    panelState.markdownVisible = false
                                }
                            }
                        )
                        .opacity(panelState.previewingFile == nil ? 1 : 0)

                        // Overlay: markdown preview when a file is open
                        if panelState.previewingFile != nil {
                            VStack(spacing: 0) {
                                MarkdownBreadcrumb(
                                    filePath: panelState.filePath,
                                    onDismiss: {
                                        withAnimation(panelTransition) {
                                            panelState.dismissPreview()
                                        }
                                    }
                                )

                                NativeMarkdownPanelView(
                                    content: $panelState.content,
                                    filePath: panelState.filePath,
                                    onClose: {
                                        withAnimation(panelTransition) {
                                            panelState.dismissPreview()
                                        }
                                    },
                                    onRefresh: { panelState.refresh() },
                                    onExecuteCode: handleExecuteCode,
                                    config: config
                                )
                            }
                            .transition(.opacity)
                        }
                    }
                }
            }
        )
        .alert("Potentially Dangerous Command", isPresented: $showDangerAlert) {
            Button("Cancel", role: .cancel) { pendingCode = nil }
            Button("Execute Anyway", role: .destructive) {
                if let code = pendingCode {
                    executeInTerminal(code)
                    pendingCode = nil
                }
            }
        } message: {
            Text("This command may be destructive. Are you sure?")
        }
        .adaptiveThemeFromSystem()
    }

    /// Handle code execution with safety check for dangerous commands
    private func handleExecuteCode(_ code: String) {
        let dangerous = ["rm -rf", "sudo rm", "dd if=", "> /dev/", "mkfs"]
        if dangerous.contains(where: { code.lowercased().contains($0) }) {
            pendingCode = code
            showDangerAlert = true
        } else {
            executeInTerminal(code)
        }
    }

    /// Send code to terminal for execution
    private func executeInTerminal(_ code: String) {
        NotificationCenter.default.post(
            name: .ghosttyInsertText,
            object: nil,
            userInfo: ["text": code]
        )
    }
}

/// Breadcrumb bar shown when a markdown file is previewed as an overlay on the diff view.
/// Displays filename with a dismiss button to return to the diff.
struct MarkdownBreadcrumb: View {
    let filePath: String?
    let onDismiss: () -> Void

    @Environment(\.adaptiveTheme) private var theme
    @State private var closeHovered = false

    private var fileName: String {
        guard let path = filePath else { return "Preview" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var body: some View {
        HStack(spacing: AdaptiveTheme.spacing8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundColor(theme.textMutedC)

            Text(fileName)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(theme.textPrimaryC)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(closeHovered ? theme.textPrimaryC : theme.textMutedC)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { closeHovered = $0 }
        }
        .padding(.horizontal, AdaptiveTheme.spacing12)
        .frame(height: 36)
        .background(theme.surfaceElevatedC)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.borderC.opacity(0.3))
                .frame(height: 0.5)
        }
    }
}

struct PanelContainer<Content: View>: View {
    let identifier: String?
    let content: Content

    @Environment(\.adaptiveTheme) private var theme

    init(identifier: String? = nil, @ViewBuilder content: () -> Content) {
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusLarge, style: .continuous)
                .fill(theme.surfaceElevatedC)
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusLarge, style: .continuous)
                .stroke(theme.borderSubtleC, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .padding(AdaptiveTheme.spacing8)
        .modifier(OptionalAccessibilityIdentifier(identifier: identifier))
    }
}

// MARK: - Notifications for Markdown Panel

extension Notification.Name {
    static let ghosttyToggleMarkdownPanel = Notification.Name("ghosttyToggleMarkdownPanel")
    /// Notification to open a markdown file in the panel. UserInfo should contain "path" key.
    static let ghosttyOpenMarkdownFile = Notification.Name("ghosttyOpenMarkdownFile")
    /// Notification to insert text into the terminal. UserInfo should contain "text" key.
    static let ghosttyInsertText = Notification.Name("ghosttyInsertText")
}

// MARK: - Markdown File Detection

enum MarkdownFileDetector {
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    /// Check if a file path points to a markdown file
    static func isMarkdownFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return markdownExtensions.contains(ext)
    }

    /// Check if a URL points to a markdown file
    static func isMarkdownFile(_ url: URL) -> Bool {
        return markdownExtensions.contains(url.pathExtension.lowercased())
    }
}
