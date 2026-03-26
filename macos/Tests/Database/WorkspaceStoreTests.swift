import Foundation
import GRDB
import Testing
@testable import Ghostty

/// Tests for WorkspaceStore CRUD operations using an in-memory GRDB database.
///
/// Each test gets an isolated in-memory database with the full schema applied,
/// ensuring no cross-test contamination and no disk I/O.
struct WorkspaceStoreTests {

    // MARK: - Helpers

    /// Creates an in-memory DatabasePool with migrations applied, then returns a WorkspaceStore.
    private func makeStore() throws -> WorkspaceStore {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let dbPool = try DatabasePool(path: ":memory:", configuration: config)

        // Apply migrations
        var migrator = DatabaseMigrator()
        Migration001_InitialSchema.register(in: &migrator)
        try migrator.migrate(dbPool)

        return WorkspaceStore(dbPool: dbPool)
    }

    // MARK: - Projects

    @Test func createProject_persistsToDatabase() throws {
        let store = try makeStore()

        let project = try store.createProject(name: "TestRepo", repoPath: "/tmp/test-repo")
        #expect(project.name == "TestRepo")
        #expect(project.repoPath == "/tmp/test-repo")

        let fetched = try store.project(byId: project.id)
        #expect(fetched.id == project.id)
        #expect(fetched.name == "TestRepo")
    }

    @Test func createProject_duplicatePath_throws() throws {
        let store = try makeStore()

        _ = try store.createProject(name: "Repo1", repoPath: "/tmp/unique-path")
        #expect(throws: (any Error).self) {
            try store.createProject(name: "Repo2", repoPath: "/tmp/unique-path")
        }
    }

    @Test func getProject_byId_returnsProject() throws {
        let store = try makeStore()

        let created = try store.createProject(name: "FindMe", repoPath: "/tmp/find-me")
        let fetched = try store.project(byId: created.id)
        #expect(fetched.name == "FindMe")
    }

    @Test func getProject_byRepoPath_returnsProject() throws {
        let store = try makeStore()

        _ = try store.createProject(name: "PathLookup", repoPath: "/tmp/path-lookup")
        let fetched = try store.project(byRepoPath: "/tmp/path-lookup")
        #expect(fetched != nil)
        #expect(fetched?.name == "PathLookup")
    }

    @Test func getProject_nonexistent_returnsNil() throws {
        let store = try makeStore()

        let fetched = try store.project(byRepoPath: "/tmp/does-not-exist")
        #expect(fetched == nil)
    }

    @Test func listProjects_returnsAllProjects() throws {
        let store = try makeStore()

        _ = try store.createProject(name: "Repo1", repoPath: "/tmp/repo1")
        _ = try store.createProject(name: "Repo2", repoPath: "/tmp/repo2")
        _ = try store.createProject(name: "Repo3", repoPath: "/tmp/repo3")

        let all = try store.allProjects()
        #expect(all.count == 3)
    }

    @Test func deleteProject_cascadesWorkspaces() throws {
        let store = try makeStore()

        let project = try store.createProject(name: "CascadeTest", repoPath: "/tmp/cascade")
        _ = try store.createWorkspace(
            projectId: project.id,
            name: "main",
            branch: "main",
            worktreePath: "/tmp/cascade"
        )

        // Verify workspace exists
        let workspaces = try store.workspaces(forProjectId: project.id)
        #expect(workspaces.count == 1)

        // Delete project — should cascade
        try store.deleteProject(id: project.id)

        // Workspace should be gone too (cascade delete)
        let remaining = try store.workspaces(forProjectId: project.id)
        #expect(remaining.count == 0)
    }

    // MARK: - Workspaces

    @Test func createWorkspace_persistsToDatabase() throws {
        let store = try makeStore()

        let project = try store.createProject(name: "Repo", repoPath: "/tmp/repo")
        let workspace = try store.createWorkspace(
            projectId: project.id,
            name: "feature",
            branch: "feature",
            worktreePath: "/tmp/repo-wt/feature"
        )

        #expect(workspace.branch == "feature")
        #expect(workspace.projectId == project.id)

        let fetched = try store.workspace(byId: workspace.id)
        #expect(fetched.branch == "feature")
    }

    @Test func createWorkspace_duplicateBranch_throws() throws {
        let store = try makeStore()

        let project = try store.createProject(name: "Repo", repoPath: "/tmp/repo-dup")
        _ = try store.createWorkspace(
            projectId: project.id,
            name: "main",
            branch: "main",
            worktreePath: "/tmp/repo-dup/wt1"
        )

        // Same project + same branch should violate unique constraint
        #expect(throws: (any Error).self) {
            try store.createWorkspace(
                projectId: project.id,
                name: "main",
                branch: "main",
                worktreePath: "/tmp/repo-dup/wt2"
            )
        }
    }

    @Test func listWorkspaces_forProject_returnsOnlyThatProject() throws {
        let store = try makeStore()

        let project1 = try store.createProject(name: "Repo1", repoPath: "/tmp/repo-a")
        let project2 = try store.createProject(name: "Repo2", repoPath: "/tmp/repo-b")

        _ = try store.createWorkspace(projectId: project1.id, name: "main", branch: "main", worktreePath: "/tmp/a/main")
        _ = try store.createWorkspace(projectId: project1.id, name: "dev", branch: "dev", worktreePath: "/tmp/a/dev")
        _ = try store.createWorkspace(projectId: project2.id, name: "main", branch: "main", worktreePath: "/tmp/b/main")

        let ws1 = try store.workspaces(forProjectId: project1.id)
        let ws2 = try store.workspaces(forProjectId: project2.id)
        #expect(ws1.count == 2)
        #expect(ws2.count == 1)
    }

    @Test func setActiveWorkspace_updatesLastActiveAt() throws {
        let store = try makeStore()

        let project = try store.createProject(name: "Repo", repoPath: "/tmp/active-test")
        let workspace = try store.createWorkspace(
            projectId: project.id,
            name: "main",
            branch: "main",
            worktreePath: "/tmp/active-test/main"
        )
        #expect(workspace.lastActiveAt == nil)

        try store.setActiveWorkspace(id: workspace.id)

        let updated = try store.workspace(byId: workspace.id)
        #expect(updated.lastActiveAt != nil)
    }

    @Test func activeWorkspaces_orderedByLastActiveAt() throws {
        let store = try makeStore()

        let project = try store.createProject(name: "Repo", repoPath: "/tmp/ordered-test")
        let ws1 = try store.createWorkspace(
            projectId: project.id, name: "a", branch: "branch-a", worktreePath: "/tmp/ordered/a"
        )
        let ws2 = try store.createWorkspace(
            projectId: project.id, name: "b", branch: "branch-b", worktreePath: "/tmp/ordered/b"
        )

        // Create sessions for both
        _ = try store.saveSession(workspaceId: ws1.id, splitTreeJSON: nil)
        _ = try store.saveSession(workspaceId: ws2.id, splitTreeJSON: nil)

        // Activate ws1 first, then ws2
        try store.setActiveWorkspace(id: ws1.id)
        // Small delay so timestamps differ
        Thread.sleep(forTimeInterval: 0.01)
        try store.setActiveWorkspace(id: ws2.id)

        let active = try store.activeWorkspaces()
        #expect(active.count == 2)
        // ws2 was activated more recently, should be first
        #expect(active[0].0.id == ws2.id)
    }

    // MARK: - Sessions

    @Test func saveSession_createsNewSession() throws {
        let store = try makeStore()

        let project = try store.createProject(name: "Repo", repoPath: "/tmp/session-test")
        let workspace = try store.createWorkspace(
            projectId: project.id, name: "main", branch: "main", worktreePath: "/tmp/session/main"
        )

        let session = try store.saveSession(
            workspaceId: workspace.id,
            splitTreeJSON: "{\"root\":null}",
            focusedSurfaceId: "abc-123"
        )

        #expect(session.workspaceId == workspace.id)
        #expect(session.splitTreeJSON == "{\"root\":null}")
        #expect(session.focusedSurfaceID == "abc-123")
        #expect(session.isActive == true)
    }

    @Test func saveSession_upserts_updatesExisting() throws {
        let store = try makeStore()

        let project = try store.createProject(name: "Repo", repoPath: "/tmp/upsert-test")
        let workspace = try store.createWorkspace(
            projectId: project.id, name: "main", branch: "main", worktreePath: "/tmp/upsert/main"
        )

        let first = try store.saveSession(workspaceId: workspace.id, splitTreeJSON: "v1")
        let second = try store.saveSession(workspaceId: workspace.id, splitTreeJSON: "v2")

        // Should be the same session updated, not a new one
        #expect(first.id == second.id)
        #expect(second.splitTreeJSON == "v2")
    }

    @Test func updateSession_updatesJSONOnly() throws {
        let store = try makeStore()

        let project = try store.createProject(name: "Repo", repoPath: "/tmp/update-json")
        let workspace = try store.createWorkspace(
            projectId: project.id, name: "main", branch: "main", worktreePath: "/tmp/update-json/main"
        )

        _ = try store.saveSession(workspaceId: workspace.id, splitTreeJSON: "original")
        try store.updateSession(workspaceId: workspace.id, splitTreeJSON: "updated")

        let session = try store.activeSession(forWorkspaceId: workspace.id)
        #expect(session?.splitTreeJSON == "updated")
    }

    @Test func deleteWorkspace_cascadesSessions() throws {
        let store = try makeStore()

        let project = try store.createProject(name: "Repo", repoPath: "/tmp/cascade-session")
        let workspace = try store.createWorkspace(
            projectId: project.id, name: "main", branch: "main", worktreePath: "/tmp/cascade-session/main"
        )
        _ = try store.saveSession(workspaceId: workspace.id, splitTreeJSON: "data")

        // Verify session exists
        let session = try store.activeSession(forWorkspaceId: workspace.id)
        #expect(session != nil)

        // Delete workspace — should cascade sessions
        try store.deleteWorkspace(id: workspace.id)

        let remaining = try store.activeSession(forWorkspaceId: workspace.id)
        #expect(remaining == nil)
    }

    // MARK: - Import Project

    @Test func importProject_createsProjectAndWorkspaces() throws {
        let store = try makeStore()

        let worktrees: [(branch: String, path: String, isMain: Bool)] = [
            (branch: "main", path: "/tmp/import/main", isMain: true),
            (branch: "feature", path: "/tmp/import/feature", isMain: false),
        ]

        let project = try store.importProject(
            repoPath: "/tmp/import",
            name: "ImportedRepo",
            worktrees: worktrees
        )

        #expect(project.name == "ImportedRepo")

        let workspaces = try store.workspaces(forProjectId: project.id)
        #expect(workspaces.count == 2)
    }

    @Test func importProject_mainWorktreeMarkedAsMain() throws {
        let store = try makeStore()

        let worktrees: [(branch: String, path: String, isMain: Bool)] = [
            (branch: "main", path: "/tmp/import-main/main", isMain: true),
            (branch: "dev", path: "/tmp/import-main/dev", isMain: false),
        ]

        let project = try store.importProject(
            repoPath: "/tmp/import-main",
            name: "MainTest",
            worktrees: worktrees
        )

        let workspaces = try store.workspaces(forProjectId: project.id)
        let mainWs = workspaces.first { $0.isMainBranch }
        #expect(mainWs != nil)
        #expect(mainWs?.branch == "main")

        let nonMainWs = workspaces.filter { !$0.isMainBranch }
        #expect(nonMainWs.count == 1)
    }
}
