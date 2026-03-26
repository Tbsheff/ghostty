import Foundation
import GRDB
import Testing
@testable import Ghostty

/// Integration tests for WorkspaceOrchestrator.
///
/// Combines a real temp git repo with an in-memory database to verify
/// the full lifecycle: import, create, delete, and workspace path computation.
struct WorkspaceOrchestratorTests {

    // MARK: - Helpers

    /// Creates an in-memory store with schema applied.
    private func makeStore() throws -> (WorkspaceStore, DatabaseQueue) {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let dbQueue = try DatabaseQueue(configuration: config)

        var migrator = DatabaseMigrator()
        Migration001_InitialSchema.register(in: &migrator)
        try migrator.migrate(dbQueue)

        let store = WorkspaceStore(dbPool: dbQueue)
        return (store, dbQueue)
    }

    /// Creates a temp directory with an initialized git repo and one empty commit.
    private func makeTempRepo() throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-orch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let path = tmp.path
        try shellSync("git init \(path)")
        try shellSync("git -C \(path) config user.email test@test.com")
        try shellSync("git -C \(path) config user.name Test")
        try shellSync("git -C \(path) commit --allow-empty -m init")
        return path
    }

    /// Creates a non-git temp directory.
    private func makeTempDir() throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-orch-nongit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp.path
    }

    private func cleanupPath(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    @discardableResult
    private func shellSync(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(command: command, stderr: "", exitCode: process.terminationStatus)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @MainActor
    private func makeOrchestrator(store: WorkspaceStore) -> WorkspaceOrchestrator {
        let git = GitWorktreeManager()
        let saver = SessionAutoSaver(store: store)
        return WorkspaceOrchestrator(store: store, git: git, sessionSaver: saver)
    }

    // MARK: - Import Project

    @Test @MainActor func importProject_validRepo_createsProjectAndWorkspaces() async throws {
        let repo = try makeTempRepo()
        defer { cleanupPath(repo) }

        let (store, _) = try makeStore()
        let orchestrator = makeOrchestrator(store: store)

        let project = try await orchestrator.importProject(path: repo)
        #expect(!project.name.isEmpty)

        let workspaces = try store.workspaces(forProjectId: project.id)
        // A fresh repo has at least one worktree (main)
        #expect(workspaces.count >= 1)
    }

    @Test @MainActor func importProject_nonGitDir_throws() async throws {
        let dir = try makeTempDir()
        defer { cleanupPath(dir) }

        let (store, _) = try makeStore()
        let orchestrator = makeOrchestrator(store: store)

        await #expect(throws: (any Error).self) {
            try await orchestrator.importProject(path: dir)
        }
    }

    @Test @MainActor func importProject_duplicate_returnsExisting() async throws {
        let repo = try makeTempRepo()
        defer { cleanupPath(repo) }

        let (store, _) = try makeStore()
        let orchestrator = makeOrchestrator(store: store)

        let first = try await orchestrator.importProject(path: repo)
        let second = try await orchestrator.importProject(path: repo)

        #expect(first.id == second.id)
    }

    // MARK: - Create Workspace

    @Test @MainActor func createWorkspace_newBranch_createsWorktreeAndRecord() async throws {
        let repo = try makeTempRepo()
        defer {
            cleanupPath(repo)
            // Clean up worktree directory
            let repoName = (repo as NSString).lastPathComponent
            let parentDir = (repo as NSString).deletingLastPathComponent
            cleanupPath("\(parentDir)/\(repoName)-worktrees")
        }

        let (store, _) = try makeStore()
        let orchestrator = makeOrchestrator(store: store)

        // Import the project first
        let project = try await orchestrator.importProject(path: repo)

        // Create a branch
        try shellSync("git -C \(repo) branch new-ws-branch")

        let workspace = try await orchestrator.createWorkspace(projectId: project.id, branch: "new-ws-branch")
        #expect(workspace.branch == "new-ws-branch")
        #expect(FileManager.default.fileExists(atPath: workspace.worktreePath))
    }

    @Test @MainActor func createWorkspace_existingBranch_createsWorktreeAndRecord() async throws {
        let repo = try makeTempRepo()
        defer {
            cleanupPath(repo)
            let repoName = (repo as NSString).lastPathComponent
            let parentDir = (repo as NSString).deletingLastPathComponent
            cleanupPath("\(parentDir)/\(repoName)-worktrees")
        }

        let (store, _) = try makeStore()
        let orchestrator = makeOrchestrator(store: store)

        let project = try await orchestrator.importProject(path: repo)
        try shellSync("git -C \(repo) branch existing-ws-branch")

        let workspace = try await orchestrator.createWorkspace(projectId: project.id, branch: "existing-ws-branch")
        #expect(workspace.branch == "existing-ws-branch")

        // Verify DB record
        let fetched = try store.workspace(byId: workspace.id)
        #expect(fetched.branch == "existing-ws-branch")
    }

    // MARK: - Delete Workspace

    @Test @MainActor func deleteWorkspace_removesWorktreeAndRecord() async throws {
        let repo = try makeTempRepo()
        defer {
            cleanupPath(repo)
            let repoName = (repo as NSString).lastPathComponent
            let parentDir = (repo as NSString).deletingLastPathComponent
            cleanupPath("\(parentDir)/\(repoName)-worktrees")
        }

        let (store, _) = try makeStore()
        let orchestrator = makeOrchestrator(store: store)

        let project = try await orchestrator.importProject(path: repo)
        try shellSync("git -C \(repo) branch delete-me-branch")
        let workspace = try await orchestrator.createWorkspace(projectId: project.id, branch: "delete-me-branch")
        let wtPath = workspace.worktreePath
        #expect(FileManager.default.fileExists(atPath: wtPath))

        try await orchestrator.deleteWorkspace(id: workspace.id)

        // Worktree should be gone from disk
        #expect(!FileManager.default.fileExists(atPath: wtPath))

        // DB record should be gone
        #expect(throws: (any Error).self) {
            try store.workspace(byId: workspace.id)
        }
    }

    @Test @MainActor func deleteWorkspace_mainBranch_throws() async throws {
        let repo = try makeTempRepo()
        defer { cleanupPath(repo) }

        let (store, _) = try makeStore()
        let orchestrator = makeOrchestrator(store: store)

        let project = try await orchestrator.importProject(path: repo)
        let workspaces = try store.workspaces(forProjectId: project.id)
        let mainWs = workspaces.first { $0.isMainBranch }
        #expect(mainWs != nil)

        await #expect(throws: WorkspaceError.self) {
            try await orchestrator.deleteWorkspace(id: mainWs!.id)
        }
    }

    // MARK: - Worktree Path Computation

    @Test @MainActor func computeWorktreePath_correctSiblingPattern() async throws {
        let repo = try makeTempRepo()
        defer {
            cleanupPath(repo)
            let repoName = (repo as NSString).lastPathComponent
            let parentDir = (repo as NSString).deletingLastPathComponent
            cleanupPath("\(parentDir)/\(repoName)-worktrees")
        }

        let (store, _) = try makeStore()
        let orchestrator = makeOrchestrator(store: store)

        let project = try await orchestrator.importProject(path: repo)
        try shellSync("git -C \(repo) branch feature/auth")

        let workspace = try await orchestrator.createWorkspace(projectId: project.id, branch: "feature/auth")

        // Path should follow pattern: <repo>/../<repoName>-worktrees/<sanitizedBranch>
        let repoName = (project.repoPath as NSString).lastPathComponent
        let parentDir = (project.repoPath as NSString).deletingLastPathComponent
        let expectedPath = (parentDir as NSString).appendingPathComponent("\(repoName)-worktrees/feature-auth")

        let resolvedExpected = (expectedPath as NSString).resolvingSymlinksInPath
        let resolvedActual = (workspace.worktreePath as NSString).resolvingSymlinksInPath
        #expect(resolvedActual == resolvedExpected)
    }
}
