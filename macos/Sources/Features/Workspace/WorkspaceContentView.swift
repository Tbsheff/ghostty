import AppKit
import SwiftUI
import GhosttyKit
import Combine

// MARK: - WorkspaceContentView

/// Manages multiple TerminalWithPanelView instances, showing only the active tab.
///
/// CRITICAL DESIGN: Only the active tab's view is in the NSView hierarchy.
/// Inactive tabs are removed from their superview (but retained in memory)
/// to prevent GPU rendering of hidden Metal surfaces while keeping PTY alive.
///
/// Follows the NativeSplitView pattern: NSViewControllerRepresentable wrapping
/// an NSViewController that manages child views at the AppKit level.
struct WorkspaceContentView: NSViewControllerRepresentable {
    let workspaceState: WorkspaceState
    let ghostty: Ghostty.App
    weak var delegate: (any TerminalViewDelegate)?

    func makeNSViewController(context: Context) -> WorkspaceContentViewController {
        let controller = WorkspaceContentViewController(
            workspaceState: workspaceState,
            ghostty: ghostty,
            delegate: delegate
        )
        return controller
    }

    func updateNSViewController(_ controller: WorkspaceContentViewController, context: Context) {
        controller.delegate = delegate
        controller.syncToActiveTab()
    }
}

// MARK: - WorkspaceContentViewController

/// The AppKit-level controller that manages tab content views.
///
/// It holds a dictionary of NSHostingView instances keyed by tab ID.
/// Only the active tab's hosting view is added as a subview. When the
/// active tab changes, the old view is removed from the superview (stopping
/// Metal rendering) and the new view is added.
class WorkspaceContentViewController: NSViewController {
    private let workspaceState: WorkspaceState
    private let ghostty: Ghostty.App
    weak var delegate: (any TerminalViewDelegate)?

    /// Retained hosting views keyed by tab ID. Views are kept in memory
    /// even when removed from the view hierarchy to preserve PTY state.
    private var tabViews: [String: NSView] = [:]

    /// The currently displayed tab ID.
    private var activeTabId: String?

    /// Combine subscription for active tab changes.
    private var cancellables = Set<AnyCancellable>()

    init(
        workspaceState: WorkspaceState,
        ghostty: Ghostty.App,
        delegate: (any TerminalViewDelegate)?
    ) {
        self.workspaceState = workspaceState
        self.ghostty = ghostty
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Subscribe to tab changes
        workspaceState.activeTabDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncToActiveTab()
            }
            .store(in: &cancellables)

        syncToActiveTab()
    }

    // MARK: - Tab Switching

    /// Synchronizes the displayed view to the current active tab.
    ///
    /// This is the core of the GPU optimization: we physically remove the
    /// old tab's view from the NSView hierarchy (stopping Metal rendering)
    /// and add only the new active tab's view.
    func syncToActiveTab() {
        guard let tab = workspaceState.currentTab else {
            // No active tab — remove current view
            removeActiveView()
            activeTabId = nil
            return
        }

        // If already showing this tab, nothing to do
        guard tab.id != activeTabId else { return }

        // Remove the current view from hierarchy (but keep in tabViews dict)
        removeActiveView()

        // Get or create the view for this tab
        let tabView = getOrCreateView(for: tab)

        // Add to hierarchy with full constraints
        tabView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: view.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        activeTabId = tab.id
    }

    private func removeActiveView() {
        guard let activeId = activeTabId, let activeView = tabViews[activeId] else { return }
        activeView.removeFromSuperview()
    }

    private func getOrCreateView(for tab: WorktreeTab) -> NSView {
        if let existing = tabViews[tab.id] {
            return existing
        }

        let hostingView = NSHostingView(
            rootView: TerminalWithPanelView(
                panelState: tab.markdownPanelState,
                config: ghostty.config
            ) {
                TerminalSplitTreeView(
                    tree: tab.surfaceTree,
                    action: { [weak self] action in
                        self?.delegate?.performSplitAction(action)
                    }
                )
                .environmentObject(ghostty)
            }
            .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
        )

        tabViews[tab.id] = hostingView
        return hostingView
    }

    // MARK: - Cleanup

    /// Removes views for tabs that no longer exist in any worktree.
    func cleanupOrphanedViews() {
        let allTabIds = Set(workspaceState.allWorktrees.flatMap(\.tabs).map(\.id))
        let orphanedIds = Set(tabViews.keys).subtracting(allTabIds)
        for id in orphanedIds {
            tabViews[id]?.removeFromSuperview()
            tabViews.removeValue(forKey: id)
        }
    }
}
