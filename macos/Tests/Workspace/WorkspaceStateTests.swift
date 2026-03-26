import Foundation
import Testing
@testable import Ghostty

/// Tests for WorkspaceState observable model.
///
/// These tests verify the in-memory state management logic without requiring
/// a database or git operations. WorkspaceState is @Observable and drives
/// the sidebar, content area, and tab bar.
struct WorkspaceStateTests {

    // MARK: - Helpers

    /// Creates a WorkspaceState populated with one repo containing two worktrees.
    @MainActor
    private func makePopulatedState() -> Ghostty.WorkspaceState {
        let state = Ghostty.WorkspaceState()
        let repo = RepoGroup(
            id: "repo-1",
            name: "TestRepo",
            repoPath: "/tmp/test-repo",
            worktrees: [
                WorktreeState(id: "wt-main", branch: "main", worktreePath: "/tmp/test-repo"),
                WorktreeState(id: "wt-feature", branch: "feature/auth", worktreePath: "/tmp/test-repo-wt/feature-auth"),
            ]
        )
        state.repos = [repo]
        return state
    }

    // MARK: - Initial State

    @Test @MainActor func initialState_noRepos_isEmpty() {
        let state = Ghostty.WorkspaceState()
        #expect(state.repos.isEmpty)
        #expect(state.selectedWorktreeId == nil)
        #expect(state.currentWorktree == nil)
    }

    // MARK: - Repo Management

    @Test @MainActor func addRepo_appearsInRepos() {
        let state = Ghostty.WorkspaceState()
        let repo = RepoGroup(id: "r1", name: "MyRepo", repoPath: "/tmp/my-repo")
        state.repos.append(repo)
        #expect(state.repos.count == 1)
        #expect(state.repos[0].name == "MyRepo")
    }

    // MARK: - Selection

    @Test @MainActor func selectWorktree_setsSelectedId() {
        let state = makePopulatedState()

        // Add a tab so selection doesn't trigger notification for missing tab
        state.repos[0].worktrees[0].tabs = [WorktreeTab(id: "tab-1")]
        state.selectWorktree("wt-main")
        #expect(state.selectedWorktreeId == "wt-main")
    }

    @Test @MainActor func selectWorktree_nonexistent_noOp() {
        let state = makePopulatedState()
        state.selectWorktree("nonexistent-id")
        // selectedWorktreeId is set but currentWorktree won't find it
        #expect(state.currentWorktree == nil)
    }

    @Test @MainActor func currentWorktree_returnsSelected() {
        let state = makePopulatedState()
        state.repos[0].worktrees[1].tabs = [WorktreeTab(id: "tab-1")]
        state.selectWorktree("wt-feature")
        let current = state.currentWorktree
        #expect(current != nil)
        #expect(current?.branch == "feature/auth")
    }

    @Test @MainActor func currentWorktree_noneSelected_returnsNil() {
        let state = makePopulatedState()
        #expect(state.selectedWorktreeId == nil)
        #expect(state.currentWorktree == nil)
    }

    // MARK: - Sidebar Visibility

    @Test @MainActor func sidebarVisible_defaultsTrue() {
        // Clear any existing UserDefaults key to test default behavior
        UserDefaults.standard.removeObject(forKey: "ghostty.workspaceSidebarVisible")
        let state = Ghostty.WorkspaceState()
        #expect(state.sidebarVisible == true)
    }

    @Test @MainActor func toggleSidebar_togglesVisibility() {
        let state = Ghostty.WorkspaceState()
        let initial = state.sidebarVisible
        state.toggleSidebar()
        #expect(state.sidebarVisible == !initial)
        state.toggleSidebar()
        #expect(state.sidebarVisible == initial)
    }

    // MARK: - Tab Management

    @Test @MainActor func addTab_appendsToCurrentWorktree() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [WorktreeTab(id: "existing")]
        state.selectWorktree("wt-main")

        let newTab = WorktreeTab(id: "new-tab")
        state.addTab(newTab)

        #expect(state.currentWorktree?.tabs.count == 2)
        #expect(state.currentWorktree?.selectedTabIndex == 1)
    }

    @Test @MainActor func removeTab_removesFromWorktree() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [
            WorktreeTab(id: "t1"),
            WorktreeTab(id: "t2"),
        ]
        state.selectWorktree("wt-main")

        state.removeTab(at: 0)
        #expect(state.currentWorktree?.tabs.count == 1)
        #expect(state.currentWorktree?.tabs[0].id == "t2")
    }

    @Test @MainActor func selectTab_changesSelectedIndex() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [
            WorktreeTab(id: "t1"),
            WorktreeTab(id: "t2"),
            WorktreeTab(id: "t3"),
        ]
        state.selectWorktree("wt-main")

        state.selectTab(at: 2)
        #expect(state.currentWorktree?.selectedTabIndex == 2)
    }

    @Test @MainActor func moveTab_reordersTabsArray() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [
            WorktreeTab(id: "t1"),
            WorktreeTab(id: "t2"),
            WorktreeTab(id: "t3"),
        ]
        state.selectWorktree("wt-main")

        state.moveTab(from: 0, to: 2)
        let ids = state.currentWorktree?.tabs.map(\.id)
        #expect(ids == ["t2", "t3", "t1"])
    }

    // MARK: - WorktreeState Properties

    @Test @MainActor func worktreeState_resolvedDisplayName_usesBranch() {
        let wt = WorktreeState(branch: "feature/auth", worktreePath: "/tmp/wt")
        #expect(wt.resolvedDisplayName == "auth")
    }

    @Test @MainActor func worktreeState_resolvedDisplayName_usesDisplayNameIfSet() {
        let wt = WorktreeState(branch: "main", worktreePath: "/tmp/wt", displayName: "Primary")
        #expect(wt.resolvedDisplayName == "Primary")
    }

    @Test @MainActor func worktreeState_currentTab_returnsSelectedTab() {
        let tab1 = WorktreeTab(id: "t1")
        let tab2 = WorktreeTab(id: "t2")
        let wt = WorktreeState(branch: "main", worktreePath: "/tmp", tabs: [tab1, tab2], selectedTabIndex: 1)
        #expect(wt.currentTab?.id == "t2")
    }

    @Test @MainActor func worktreeState_currentTab_emptyTabs_returnsNil() {
        let wt = WorktreeState(branch: "main", worktreePath: "/tmp")
        #expect(wt.currentTab == nil)
    }

    @Test @MainActor func worktreeState_status_noAgents_isIdle() {
        let wt = WorktreeState(
            branch: "main",
            worktreePath: "/tmp",
            tabs: [WorktreeTab(id: "t1", agentName: nil)]
        )
        #expect(wt.status == .idle)
    }

    @Test @MainActor func worktreeState_status_withAgent_isActiveAgent() {
        let wt = WorktreeState(
            branch: "main",
            worktreePath: "/tmp",
            tabs: [WorktreeTab(id: "t1", agentName: "claude")]
        )
        #expect(wt.status == .activeAgent)
    }

    // MARK: - RepoGroup

    @Test @MainActor func repoGroup_avatarLetter_returnsFirstLetter() {
        let repo = RepoGroup(name: "ghostty", repoPath: "/tmp/ghostty")
        #expect(repo.avatarLetter == "G")
    }
}
