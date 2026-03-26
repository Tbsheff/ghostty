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
    private func makePopulatedState() -> WorkspaceState {
        let state = WorkspaceState()
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
        let state = WorkspaceState()
        #expect(state.repos.isEmpty)
        #expect(state.selectedWorktreeId == nil)
        #expect(state.currentWorktree == nil)
    }

    // MARK: - Repo Management

    @Test @MainActor func addRepo_appearsInRepos() {
        let state = WorkspaceState()
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
        let state = WorkspaceState()
        #expect(state.sidebarVisible == true)
    }

    @Test @MainActor func toggleSidebar_togglesVisibility() {
        let state = WorkspaceState()
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

    // MARK: - Tab Behavior (WorkspaceTabBar / WorkspaceContentView)

    @Test @MainActor func testAddTab_appendsToWorktree() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [WorktreeTab(id: "existing")]
        state.selectWorktree("wt-main")

        state.addTab(WorktreeTab(id: "new1"))
        state.addTab(WorktreeTab(id: "new2"))

        #expect(state.currentWorktree?.tabs.count == 3)
        #expect(state.currentWorktree?.tabs.last?.id == "new2")
    }

    @Test @MainActor func testRemoveTab_removesFromWorktree() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [
            WorktreeTab(id: "a"),
            WorktreeTab(id: "b"),
            WorktreeTab(id: "c"),
        ]
        state.selectWorktree("wt-main")

        state.removeTab(at: 1) // remove "b"
        let ids = state.currentWorktree?.tabs.map(\.id)
        #expect(ids == ["a", "c"])
    }

    @Test @MainActor func testRemoveLastTab_leavesEmptyWorktree() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [WorktreeTab(id: "only")]
        state.selectWorktree("wt-main")

        state.removeTab(at: 0)
        #expect(state.currentWorktree?.tabs.isEmpty == true)
        #expect(state.currentWorktree?.selectedTabIndex == 0)
    }

    @Test @MainActor func testSelectTab_updatesSelectedIndex() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [
            WorktreeTab(id: "a"),
            WorktreeTab(id: "b"),
            WorktreeTab(id: "c"),
        ]
        state.selectWorktree("wt-main")

        state.selectTab(at: 2)
        #expect(state.currentWorktree?.selectedTabIndex == 2)
        #expect(state.currentTab?.id == "c")
    }

    @Test @MainActor func testMoveTab_reordersCorrectly() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [
            WorktreeTab(id: "a"),
            WorktreeTab(id: "b"),
            WorktreeTab(id: "c"),
            WorktreeTab(id: "d"),
        ]
        state.selectWorktree("wt-main")

        state.moveTab(from: 3, to: 1) // move "d" to index 1
        let ids = state.currentWorktree?.tabs.map(\.id)
        #expect(ids == ["a", "d", "b", "c"])
        #expect(state.currentWorktree?.selectedTabIndex == 1)
    }

    @Test @MainActor func testRemoveTab_adjustsSelectedIndex() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [
            WorktreeTab(id: "a"),
            WorktreeTab(id: "b"),
            WorktreeTab(id: "c"),
        ]
        state.selectWorktree("wt-main")
        state.selectTab(at: 2) // select "c"

        state.removeTab(at: 2) // remove "c"
        // Should adjust to last valid index
        #expect(state.currentWorktree?.selectedTabIndex == 1)
    }

    @Test @MainActor func testRemoveRepo_clearsSelection() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [WorktreeTab(id: "t")]
        state.selectWorktree("wt-main")
        #expect(state.selectedWorktreeId == "wt-main")

        let repo = state.repos[0]
        state.removeRepo(repo)

        #expect(state.repos.isEmpty)
        #expect(state.selectedWorktreeId == nil)
    }

    @Test @MainActor func testRemoveWorktree_selectsAnother() {
        let state = makePopulatedState()
        state.repos[0].worktrees[0].tabs = [WorktreeTab(id: "t1")]
        state.repos[0].worktrees[1].tabs = [WorktreeTab(id: "t2")]
        state.selectWorktree("wt-main")

        state.removeWorktree("wt-main", from: "repo-1")

        // Should auto-select the remaining worktree
        #expect(state.selectedWorktreeId == "wt-feature")
    }

    // MARK: - Git Panel Visibility

    @Test @MainActor func testToggleGitPanel_togglesVisibility() {
        let state = WorkspaceState()
        let initial = state.gitPanelVisible
        state.toggleGitPanel()
        #expect(state.gitPanelVisible == !initial)
    }
}
