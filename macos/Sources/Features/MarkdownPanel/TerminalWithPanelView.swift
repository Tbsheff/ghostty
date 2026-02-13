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

    init() {
        let defaults = UserDefaults.standard
        self.fileBrowserVisible = defaults.bool(forKey: Self.fileBrowserVisibleKey)
        self.markdownVisible = defaults.bool(forKey: Self.markdownVisibleKey)
    }

    /// Load a markdown file asynchronously
    func loadFile(at path: String) {
        filePath = path
        stopWatching()

        // Show panel immediately for responsiveness
        markdownVisible = true

        // Read file on background queue to avoid blocking UI
        Task.detached(priority: .userInitiated) {
            do {
                let fileContent = try String(contentsOfFile: path, encoding: .utf8)
                await MainActor.run {
                    self.content = fileContent
                    self.startWatching(path: path)
                }
            } catch {
                await MainActor.run {
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

    /// Toggle just the markdown preview
    func toggleMarkdown() {
        markdownVisible.toggle()
    }

    /// Start watching a file for changes with debouncing
    private func startWatching(path: String) {
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
            self.debounceTimer = Timer.scheduledTimer(withTimeInterval: self.debounceInterval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
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
    /// Clamped to prevent invalid persisted values from causing layout issues
    @AppStorage("ghostty.fileBrowserWidth") private var fileBrowserWidth: Double = {
        let stored = UserDefaults.standard.double(forKey: "ghostty.fileBrowserWidth")
        return stored > 0 ? min(stored, 400) : 240
    }()

    /// Width of the markdown panel (persisted via AppStorage)
    /// Clamped to prevent invalid persisted values from causing layout issues
    @AppStorage("ghostty.markdownWidth") private var markdownWidth: Double = {
        let stored = UserDefaults.standard.double(forKey: "ghostty.markdownWidth")
        return stored > 0 ? min(stored, 400) : 300
    }()

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
                get: { CGFloat(fileBrowserWidth) },
                set: { fileBrowserWidth = Double($0) }
            ),
            rightWidth: Binding(
                get: { CGFloat(markdownWidth) },
                set: { markdownWidth = Double($0) }
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
                PanelContainer(identifier: "markdown.panel") {
                    // Native Swift markdown renderer - no WebKit/JS needed!
                    NativeMarkdownPanelView(
                        content: $panelState.content,
                        filePath: panelState.filePath,
                        onClose: {
                            withAnimation(panelTransition) {
                                panelState.markdownVisible = false
                            }
                        },
                        onRefresh: {
                            panelState.refresh()
                        },
                        onExecuteCode: handleExecuteCode,
                        config: config
                    )
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
        )
        .padding(AdaptiveTheme.spacing8)
        .modifier(AccessibilityIdentifierModifier(identifier: identifier))
    }
}

struct AccessibilityIdentifierModifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

/// A modern draggable divider with visual feedback
struct ModernDivider: View {
    @Binding var position: CGFloat
    let minValue: CGFloat
    let maxValue: CGFloat
    var inverted: Bool = false

    @Environment(\.adaptiveTheme) private var theme
    @State private var isDragging = false
    @State private var isHovered = false
    @State private var dragStartPosition: CGFloat = 0

    private var dividerColor: Color {
        if isDragging {
            return theme.accentC
        } else if isHovered {
            return theme.textMutedC
        } else {
            return theme.borderC
        }
    }

    var body: some View {
        // Visual divider line (1px, expands to 3px on interaction)
        Rectangle()
            .fill(dividerColor)
            .frame(width: isDragging || isHovered ? 3 : 1)
            .animation(.easeOut(duration: AdaptiveTheme.animationFast), value: isDragging)
            .animation(.easeOut(duration: AdaptiveTheme.animationFast), value: isHovered)
            .overlay(
                // Invisible drag handle extends beyond visual divider
                Color.clear
                    .frame(width: 16)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    dragStartPosition = position
                                }
                                let delta = inverted ? -value.translation.width : value.translation.width
                                let newPosition = dragStartPosition + delta
                                position = max(minValue, min(maxValue, newPosition))
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
                    .onHover { hovering in
                        isHovered = hovering
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            )
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
