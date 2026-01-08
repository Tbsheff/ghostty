import SwiftUI
import GhosttyKit
import Combine
import os

/// This delegate is notified of actions and property changes regarding the terminal view. This
/// delegate is optional and can be used by a TerminalView caller to react to changes such as
/// titles being set, cell sizes being changed, etc.
protocol TerminalViewDelegate: AnyObject {
    /// Called when the currently focused surface changed. This can be nil.
    func focusedSurfaceDidChange(to: Ghostty.SurfaceView?)

    /// The URL of the pwd should change.
    func pwdDidChange(to: URL?)

    /// The cell size changed.
    func cellSizeDidChange(to: NSSize)

    /// Perform an action. At the time of writing this is only triggered by the command palette.
    func performAction(_ action: String, on: Ghostty.SurfaceView)
    
    /// A split tree operation
    func performSplitAction(_ action: TerminalSplitOperation)
}

/// The view model is a required implementation for TerminalView callers. This contains
/// the main state between the TerminalView caller and SwiftUI. This abstraction is what
/// allows AppKit to own most of the data in SwiftUI.
protocol TerminalViewModel: ObservableObject {
    /// The tree of terminal surfaces (splits) within the view. This is mutated by TerminalView
    /// and children. This should be @Published.
    var surfaceTree: SplitTree<Ghostty.SurfaceView> { get set }

    /// The command palette state.
    var commandPaletteIsShowing: Bool { get set }

    /// The update overlay should be visible.
    var updateOverlayIsVisible: Bool { get }

    /// The markdown panel state for this terminal.
    var markdownPanelState: MarkdownPanelState { get }
}

/// The main terminal view. This terminal view supports splits.
struct TerminalView<ViewModel: TerminalViewModel>: View {
    @ObservedObject var ghostty: Ghostty.App

    // The required view model
    @ObservedObject var viewModel: ViewModel

    // An optional delegate to receive information about terminal changes.
    weak var delegate: (any TerminalViewDelegate)? = nil
    
    // The most recently focused surface, equal to focusedSurface when
    // it is non-nil.
    @State private var lastFocusedSurface: Weak<Ghostty.SurfaceView> = .init()

    // Combine cancellable for observing the focused surface's pwd changes
    @State private var pwdCancellable: AnyCancellable?

    // This seems like a crutch after switching from SwiftUI to AppKit lifecycle.
    @FocusState private var focused: Bool

    // Various state values sent back up from the currently focused terminals.
    @FocusedValue(\.ghosttySurfaceView) private var focusedSurface
    @FocusedValue(\.ghosttySurfacePwd) private var surfacePwd
    @FocusedValue(\.ghosttySurfaceCellSize) private var cellSize

    // The pwd of the focused surface as a URL
    // Try FocusedValue first, fall back to direct surface access
    private var pwdURL: URL? {
        // First try FocusedValue
        if let surfacePwd, !surfacePwd.isEmpty {
            return URL(fileURLWithPath: surfacePwd)
        }
        // Fallback: get pwd directly from the last focused surface
        if let pwd = lastFocusedSurface.value?.pwd, !pwd.isEmpty {
            return URL(fileURLWithPath: pwd)
        }
        return nil
    }

    var body: some View {
        switch ghostty.readiness {
        case .loading:
            Text("Loading")
        case .error:
            ErrorView()
        case .ready:
            TerminalWithPanelView(panelState: viewModel.markdownPanelState, config: ghostty.config) {
                ZStack {
                    VStack(spacing: 0) {
                        // If we're running in debug mode we show a warning so that users
                        // know that performance will be degraded.
                        if (Ghostty.info.mode == GHOSTTY_BUILD_MODE_DEBUG || Ghostty.info.mode == GHOSTTY_BUILD_MODE_RELEASE_SAFE) {
                            DebugBuildWarningView()
                        }

                        TerminalSplitTreeView(
                            tree: viewModel.surfaceTree,
                            action: { delegate?.performSplitAction($0) })
                            .environmentObject(ghostty)
                            .focused($focused)
                            .onAppear { self.focused = true }
                            .onChange(of: focusedSurface) { newValue in
                                // We want to keep track of our last focused surface so even if
                                // we lose focus we keep this set to the last non-nil value.
                                if let surface = newValue {
                                    lastFocusedSurface = .init(surface)
                                    self.delegate?.focusedSurfaceDidChange(to: surface)

                                    // Subscribe to this surface's pwd changes for file browser sync
                                    subscribeToPwdChanges(surface: surface)
                                }
                            }
                            .onChange(of: pwdURL) { newValue in
                                self.delegate?.pwdDidChange(to: newValue)
                                // Update file browser root path when pwd changes
                                if let url = newValue {
                                    viewModel.markdownPanelState.browserRootPath = url.path
                                }
                            }
                            .onAppear {
                                // Initial sync: subscribe to surface pwd and set initial value
                                if let surface = focusedSurface ?? lastFocusedSurface.value {
                                    subscribeToPwdChanges(surface: surface)
                                }
                                // Sync file browser CWD (with retry for timing issues)
                                syncFileBrowserToTerminalPwd()
                            }
                            .onChange(of: viewModel.markdownPanelState.fileBrowserVisible) { visible in
                                // Sync CWD when file browser opens
                                if visible {
                                    syncFileBrowserToTerminalPwd()
                                }
                            }
                            .onDisappear {
                                // Cancel pwd subscription when view disappears to prevent
                                // dangling subscriptions and potential crashes
                                pwdCancellable?.cancel()
                                pwdCancellable = nil
                            }
                            .onChange(of: cellSize) { newValue in
                                guard let size = newValue else { return }
                                self.delegate?.cellSizeDidChange(to: size)
                            }
                            .frame(idealWidth: lastFocusedSurface.value?.initialSize?.width,
                                   idealHeight: lastFocusedSurface.value?.initialSize?.height)
                    }
                    // Ignore safe area to extend up in to the titlebar region if we have the "hidden" titlebar style
                    .ignoresSafeArea(.container, edges: ghostty.config.macosTitlebarStyle == "hidden" ? .top : [])

                    if let surfaceView = lastFocusedSurface.value {
                        TerminalCommandPaletteView(
                            surfaceView: surfaceView,
                            isPresented: $viewModel.commandPaletteIsShowing,
                            ghosttyConfig: ghostty.config,
                            updateViewModel: (NSApp.delegate as? AppDelegate)?.updateViewModel) { action in
                            self.delegate?.performAction(action, on: surfaceView)
                        }
                    }

                    // Show update information above all else.
                    if viewModel.updateOverlayIsVisible {
                        UpdateOverlay()
                    }
                }
            }
            .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
        }
    }


    /// Subscribe to a surface's pwd publisher to update file browser root path
    private func subscribeToPwdChanges(surface: Ghostty.SurfaceView) {
        // Cancel any existing subscription
        pwdCancellable?.cancel()

        // Subscribe to the surface's pwd changes
        pwdCancellable = surface.$pwd
            .receive(on: DispatchQueue.main)
            .sink { [weak viewModel] newPwd in
                guard let viewModel = viewModel else { return }
                if let pwd = newPwd, !pwd.isEmpty {
                    viewModel.markdownPanelState.browserRootPath = pwd
                }
            }

        // Also set immediately if pwd is already available
        if let pwd = surface.pwd, !pwd.isEmpty {
            viewModel.markdownPanelState.browserRootPath = pwd
        }
    }

    /// Sync file browser to terminal's current working directory
    /// Tries multiple sources since FocusedValue may not be available immediately
    private func syncFileBrowserToTerminalPwd(retryCount: Int = 0) {
        // Try 1: Get pwd from last focused surface (most reliable)
        if let surface = lastFocusedSurface.value, let pwd = surface.pwd, !pwd.isEmpty {
            viewModel.markdownPanelState.browserRootPath = pwd
            return
        }

        // Try 2: Get pwd from currently focused surface
        if let surface = focusedSurface, let pwd = surface.pwd, !pwd.isEmpty {
            viewModel.markdownPanelState.browserRootPath = pwd
            return
        }

        // Try 3: Get pwd from FocusedValue (may be stale but better than nothing)
        if let surfacePwd = surfacePwd, !surfacePwd.isEmpty {
            viewModel.markdownPanelState.browserRootPath = surfacePwd
            return
        }

        // Try 4: Find any surface in the tree and get its pwd
        if let surface = findFirstSurface(in: viewModel.surfaceTree) {
            if let pwd = surface.pwd, !pwd.isEmpty {
                viewModel.markdownPanelState.browserRootPath = pwd
                return
            }

            // Subscribe to this surface for future updates
            subscribeToPwdChanges(surface: surface)
        }

        // Retry a few times with delay - pwd may not be available immediately
        // (shell needs time to report via OSC 7)
        if retryCount < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                syncFileBrowserToTerminalPwd(retryCount: retryCount + 1)
            }
        }
    }

    /// Find the first surface in a split tree
    private func findFirstSurface(in tree: SplitTree<Ghostty.SurfaceView>) -> Ghostty.SurfaceView? {
        guard let root = tree.root else { return nil }
        return findFirstSurface(in: root)
    }

    /// Recursive helper to find surface in a node
    private func findFirstSurface(in node: SplitTree<Ghostty.SurfaceView>.Node) -> Ghostty.SurfaceView? {
        switch node {
        case .leaf(let view):
            return view
        case .split(let split):
            return findFirstSurface(in: split.left) ?? findFirstSurface(in: split.right)
        }
    }
}

fileprivate struct UpdateOverlay: View {
    var body: some View {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    UpdatePill(model: appDelegate.updateViewModel)
                        .padding(.bottom, 9)
                        .padding(.trailing, 9)
                }
            }
        }
    }
}

struct DebugBuildWarningView: View {
    @State private var isPopover = false

    var body: some View {
        HStack {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            Text("You're running a debug build of Ghostty! Performance will be degraded.")
                .padding(.all, 8)
                .popover(isPresented: $isPopover, arrowEdge: .bottom) {
                    Text("""
                    Debug builds of Ghostty are very slow and you may experience
                    performance problems. Debug builds are only recommended during
                    development.
                    """)
                    .padding(.all)
                }

            Spacer()
        }
        .background(Color(.windowBackgroundColor))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Debug build warning")
        .accessibilityValue("Debug builds of Ghostty are very slow and you may experience performance problems. Debug builds are only recommended during development.")
        .accessibilityAddTraits(.isStaticText)
        .onTapGesture {
            isPopover = true
        }
    }
}
