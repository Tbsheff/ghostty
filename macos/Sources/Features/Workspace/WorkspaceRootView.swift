import SwiftUI
import GhosttyKit
import Combine

// MARK: - WorkspaceRootView

/// The top-level SwiftUI view that replaces TerminalView in TerminalController.
///
/// Layout: sidebar (left) | tab bar + content (center) | git panel (right)
/// Uses NativeSplitView for the 3-pane layout, matching the existing
/// NativeSplitView pattern from TerminalWithPanelView.
struct WorkspaceRootView: View {
    @ObservedObject var ghostty: Ghostty.App
    let workspaceState: WorkspaceState
    weak var delegate: (any TerminalViewDelegate)?

    /// Sidebar width (persisted)
    @AppStorage("ghostty.workspaceSidebarWidth") private var sidebarWidth: Double = 220

    /// Git panel width (persisted)
    @AppStorage("ghostty.gitPanelWidth") private var gitPanelWidth: Double = 320

    /// Panel width constraints
    private let minSidebarWidth: CGFloat = 180
    private let maxSidebarWidth: CGFloat = 350
    private let minGitPanelWidth: CGFloat = 240
    private let maxGitPanelWidth: CGFloat = 500

    var body: some View {
        switch ghostty.readiness {
        case .loading:
            Text("Loading")
        case .error:
            ErrorView()
        case .ready:
            NativeSplitView(
                leftVisible: Binding(
                    get: { workspaceState.sidebarVisible },
                    set: { workspaceState.sidebarVisible = $0 }
                ),
                rightVisible: Binding(
                    get: { workspaceState.gitPanelVisible },
                    set: { workspaceState.gitPanelVisible = $0 }
                ),
                leftWidth: Binding(
                    get: { max(minSidebarWidth, min(maxSidebarWidth, CGFloat(sidebarWidth))) },
                    set: { sidebarWidth = Double(max(minSidebarWidth, min(maxSidebarWidth, $0))) }
                ),
                rightWidth: Binding(
                    get: { max(minGitPanelWidth, min(maxGitPanelWidth, CGFloat(gitPanelWidth))) },
                    set: { gitPanelWidth = Double(max(minGitPanelWidth, min(maxGitPanelWidth, $0))) }
                ),
                left: {
                    WorkspaceSidebarView(workspaceState: workspaceState)
                },
                center: {
                    // Tab bar + active tab content
                    PanelContainer(identifier: "workspace.content") {
                        WorkspaceCenterView(
                            workspaceState: workspaceState,
                            ghostty: ghostty,
                            delegate: delegate
                        )
                    }
                },
                right: {
                    // Git panel — placeholder for Stream C
                    PanelContainer(identifier: "workspace.gitpanel") {
                        GitPanelPlaceholder()
                    }
                }
            )
            .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
        }
    }
}

// MARK: - WorkspaceCenterView

/// The center pane: tab bar on top, active tab content below.
private struct WorkspaceCenterView: View {
    let workspaceState: WorkspaceState
    @ObservedObject var ghostty: Ghostty.App
    weak var delegate: (any TerminalViewDelegate)?

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — only show when there are tabs
            if let worktree = workspaceState.currentWorktree, !worktree.tabs.isEmpty {
                WorkspaceTabBar(
                    tabs: worktree.tabs,
                    selectedIndex: worktree.selectedTabIndex,
                    onSelectTab: { index in
                        workspaceState.selectTab(at: index)
                    },
                    onCloseTab: { index in
                        workspaceState.removeTab(at: index)
                    },
                    onNewTab: {
                        // Will be wired to create new terminal tab
                        NotificationCenter.default.post(
                            name: .workspaceNewTab,
                            object: nil
                        )
                    },
                    onReorderTab: { source, dest in
                        workspaceState.moveTab(from: source, to: dest)
                    }
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.borderSubtleC)
                        .frame(height: 0.5)
                }
            }

            // Content area — NSViewControllerRepresentable for Metal surface management
            // activeTabId is passed as a stored value so SwiftUI diffs it and
            // calls updateNSViewController when the active tab changes.
            WorkspaceContentView(
                workspaceState: workspaceState,
                ghostty: ghostty,
                delegate: delegate,
                activeTabId: workspaceState.currentTab?.id
            )
        }
    }
}

// MARK: - Placeholders

/// Placeholder sidebar view until Stream B implements WorkspaceSidebarView.
struct WorkspaceSidebarPlaceholder: View {
    let workspaceState: WorkspaceState

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            Text("Workspaces")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textPrimaryC)

            if workspaceState.repos.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 24))
                        .foregroundColor(theme.textMutedC)
                    Text("Add Repository")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textMutedC)
                }
                Spacer()
            } else {
                List {
                    ForEach(workspaceState.repos) { repo in
                        Section(repo.name) {
                            ForEach(repo.worktrees) { wt in
                                HStack {
                                    Image(systemName: "arrow.branch")
                                        .font(.system(size: 10))
                                    Text(wt.branch)
                                        .font(.system(size: 12))
                                    Spacer()
                                    if let stats = wt.diffStats {
                                        Text("+\(stats.added)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green)
                                        Text("-\(stats.removed)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    workspaceState.selectWorktree(wt.id)
                                }
                                .background(
                                    workspaceState.selectedWorktreeId == wt.id
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.clear
                                )
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .padding(.top, 12)
    }
}

/// Placeholder git panel view until Stream C implements GitChangesPanel.
struct GitPanelPlaceholder: View {
    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 24))
                .foregroundColor(theme.textMutedC)
            Text("Git Changes")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.textMutedC)
            Text("Coming soon")
                .font(.system(size: 11))
                .foregroundColor(theme.textMutedC.opacity(0.6))
            Spacer()
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let workspaceNewTab = Notification.Name("com.ghostty.workspace.newTab")
}
