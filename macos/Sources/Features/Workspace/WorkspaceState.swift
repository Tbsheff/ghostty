import Foundation
import SwiftUI
import Combine
import GhosttyKit

// MARK: - WorktreeTab

/// A single tab within a worktree — either a plain terminal or an agent session.
@Observable
final class WorktreeTab: Identifiable {
    let id: String
    var surfaceTree: SplitTree<Ghostty.SurfaceView>
    var markdownPanelState: MarkdownPanelState
    var focusedSurface: Ghostty.SurfaceView?
    var tabColor: TerminalTabColor
    var agentName: String?

    var title: String {
        if let agentName {
            return agentName
        }
        // Use the focused surface title or fallback
        return focusedSurface?.title ?? "Terminal"
    }

    init(
        id: String = UUID().uuidString,
        surfaceTree: SplitTree<Ghostty.SurfaceView> = .init(),
        markdownPanelState: MarkdownPanelState? = nil,
        focusedSurface: Ghostty.SurfaceView? = nil,
        tabColor: TerminalTabColor = .none,
        agentName: String? = nil
    ) {
        self.id = id
        self.surfaceTree = surfaceTree
        if let markdownPanelState {
            self.markdownPanelState = markdownPanelState
        } else {
            self.markdownPanelState = MainActor.assumeIsolated { MarkdownPanelState() }
        }
        self.focusedSurface = focusedSurface
        self.tabColor = tabColor
        self.agentName = agentName
    }
}

// MARK: - WorktreeState

/// Agent activity status for a worktree, shown as a colored dot in the sidebar.
enum WorktreeStatus {
    case idle
    case activeAgent
    case running

    var dotColor: String {
        switch self {
        case .idle: return "blue"
        case .activeAgent: return "green"
        case .running: return "orange"
        }
    }
}

/// Represents a single git worktree in the sidebar.
@Observable
final class WorktreeState: Identifiable {
    let id: String
    var branch: String
    var worktreePath: String
    var isMainBranch: Bool
    var tabs: [WorktreeTab]
    var selectedTabIndex: Int
    var diffStats: DiffStats?
    var lastActiveAt: Date?
    var ticketReference: String?
    var displayName: String?

    /// Computed status based on active agent tabs.
    var status: WorktreeStatus {
        let agentTabs = tabs.filter { $0.agentName != nil }
        guard !agentTabs.isEmpty else { return .idle }
        // If any agent tab exists, consider it active
        return .activeAgent
    }

    /// The name shown in the sidebar (falls back to branch short name).
    var resolvedDisplayName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        // Use last path component of branch for display
        if let lastSlash = branch.lastIndex(of: "/") {
            return String(branch[branch.index(after: lastSlash)...])
        }
        return branch
    }

    var currentTab: WorktreeTab? {
        guard selectedTabIndex >= 0, selectedTabIndex < tabs.count else { return nil }
        return tabs[selectedTabIndex]
    }

    init(
        id: String = UUID().uuidString,
        branch: String,
        worktreePath: String,
        isMainBranch: Bool = false,
        tabs: [WorktreeTab] = [],
        selectedTabIndex: Int = 0,
        diffStats: DiffStats? = nil,
        lastActiveAt: Date? = nil,
        ticketReference: String? = nil,
        displayName: String? = nil
    ) {
        self.id = id
        self.branch = branch
        self.worktreePath = worktreePath
        self.isMainBranch = isMainBranch
        self.tabs = tabs
        self.selectedTabIndex = selectedTabIndex
        self.diffStats = diffStats
        self.lastActiveAt = lastActiveAt
        self.ticketReference = ticketReference
        self.displayName = displayName
    }
}

// MARK: - RepoGroup

/// A group of worktrees belonging to a single git repository.
@Observable
final class RepoGroup: Identifiable {
    let id: String
    var name: String
    var repoPath: String
    var worktrees: [WorktreeState]
    var isExpanded: Bool

    /// Stable avatar color derived from repo name hash.
    var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .cyan, .yellow, .mint]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }

    /// First letter of the repo name for avatar display.
    var avatarLetter: String {
        String(name.prefix(1)).uppercased()
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        repoPath: String,
        worktrees: [WorktreeState] = [],
        isExpanded: Bool = true
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.worktrees = worktrees
        self.isExpanded = isExpanded
    }
}

// MARK: - WorkspaceState

/// The root observable state for the entire workspace.
///
/// Owned by TerminalController, this drives the sidebar, content area, and tab bar.
/// It bridges between the persistent DB records (via WorkspaceOrchestrator) and
/// the live UI state.
@Observable
final class WorkspaceState {
    var repos: [RepoGroup] = []
    var selectedWorktreeId: String?
    var sidebarVisible: Bool
    var gitPanelVisible: Bool

    /// Publisher that fires when the active tab changes (for Combine subscriptions).
    let activeTabDidChange = PassthroughSubject<WorktreeTab?, Never>()

    var currentWorktree: WorktreeState? {
        guard let id = selectedWorktreeId else { return nil }
        for repo in repos {
            if let wt = repo.worktrees.first(where: { $0.id == id }) {
                return wt
            }
        }
        return nil
    }

    var currentTab: WorktreeTab? {
        currentWorktree?.currentTab
    }

    /// All worktrees across all repos, flattened.
    var allWorktrees: [WorktreeState] {
        repos.flatMap(\.worktrees)
    }

    init() {
        self.sidebarVisible = UserDefaults.standard.bool(forKey: "ghostty.workspaceSidebarVisible")
        self.gitPanelVisible = UserDefaults.standard.bool(forKey: "ghostty.gitPanelVisible")
    }

    // MARK: - Selection

    func selectWorktree(_ id: String) {
        guard selectedWorktreeId != id else { return }
        selectedWorktreeId = id
        activeTabDidChange.send(currentTab)
    }

    // MARK: - Tab Management

    func addTab(_ tab: WorktreeTab, to worktreeId: String? = nil) {
        let targetId = worktreeId ?? selectedWorktreeId
        guard let targetId, let worktree = findWorktree(id: targetId) else { return }
        worktree.tabs.append(tab)
        worktree.selectedTabIndex = worktree.tabs.count - 1
        activeTabDidChange.send(tab)
    }

    func removeTab(at index: Int, from worktreeId: String? = nil) {
        let targetId = worktreeId ?? selectedWorktreeId
        guard let targetId, let worktree = findWorktree(id: targetId) else { return }
        guard index >= 0, index < worktree.tabs.count else { return }

        worktree.tabs.remove(at: index)

        // Adjust selected index
        if worktree.tabs.isEmpty {
            worktree.selectedTabIndex = 0
        } else if worktree.selectedTabIndex >= worktree.tabs.count {
            worktree.selectedTabIndex = worktree.tabs.count - 1
        }

        activeTabDidChange.send(worktree.currentTab)
    }

    func selectTab(at index: Int, in worktreeId: String? = nil) {
        let targetId = worktreeId ?? selectedWorktreeId
        guard let targetId, let worktree = findWorktree(id: targetId) else { return }
        guard index >= 0, index < worktree.tabs.count else { return }
        guard worktree.selectedTabIndex != index else { return }

        worktree.selectedTabIndex = index
        activeTabDidChange.send(worktree.currentTab)
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int, in worktreeId: String? = nil) {
        let targetId = worktreeId ?? selectedWorktreeId
        guard let targetId, let worktree = findWorktree(id: targetId) else { return }
        guard sourceIndex >= 0, sourceIndex < worktree.tabs.count else { return }
        guard destinationIndex >= 0, destinationIndex < worktree.tabs.count else { return }
        guard sourceIndex != destinationIndex else { return }

        let tab = worktree.tabs.remove(at: sourceIndex)
        worktree.tabs.insert(tab, at: destinationIndex)

        // Keep the same tab selected
        worktree.selectedTabIndex = destinationIndex
    }

    // MARK: - Sidebar Persistence

    func toggleSidebar() {
        sidebarVisible.toggle()
        UserDefaults.standard.set(sidebarVisible, forKey: "ghostty.workspaceSidebarVisible")
    }

    func toggleGitPanel() {
        gitPanelVisible.toggle()
        UserDefaults.standard.set(gitPanelVisible, forKey: "ghostty.gitPanelVisible")
    }

    // MARK: - Private

    private func findWorktree(id: String) -> WorktreeState? {
        for repo in repos {
            if let wt = repo.worktrees.first(where: { $0.id == id }) {
                return wt
            }
        }
        return nil
    }
}
