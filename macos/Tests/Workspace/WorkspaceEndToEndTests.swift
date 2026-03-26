import Foundation
import GRDB
import Testing
@testable import Ghostty

/// End-to-end workflow test: import repo -> create worktree -> switch -> delete.
struct WorkspaceEndToEndTests {

    // MARK: - Helpers

    private func makeStore() throws -> WorkspaceStore {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let dbQueue = try DatabaseQueue(configuration: config)

        var migrator = DatabaseMigrator()
        Migration001_InitialSchema.register(in: &migrator)
        try migrator.migrate(dbQueue)

        return WorkspaceStore(dbPool: dbQueue)
    }

    private func makeTempRepo() throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-e2e-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let path = tmp.path
        try shellSync("git init \(path)")
        try shellSync("git -C \(path) config user.email test@test.com")
        try shellSync("git -C \(path) config user.name Test")
        try shellSync("git -C \(path) commit --allow-empty -m init")
        return path
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

    // MARK: - Full Workflow

    @Test @MainActor func testFullWorkflow_importRepo_createWorktree_switchWorktree_deleteWorktree() async throws {
        let repo = try makeTempRepo()
        defer {
            cleanupPath(repo)
            let repoName = (repo as NSString).lastPathComponent
            let parentDir = (repo as NSString).deletingLastPathComponent
            cleanupPath("\(parentDir)/\(repoName)-worktrees")
        }

        let store = try makeStore()
        let orchestrator = makeOrchestrator(store: store)

        // Step 1: Import repository
        let project = try await orchestrator.importProject(path: repo)
        #expect(!project.name.isEmpty)

        let workspaces = try store.workspaces(forProjectId: project.id)
        #expect(workspaces.count >= 1)
        let mainWorkspace = workspaces.first { $0.isMainBranch }
        #expect(mainWorkspace != nil)

        // Step 2: Create a new worktree
        try shellSync("git -C \(repo) branch feature/e2e-test")
        let newWorkspace = try await orchestrator.createWorkspace(projectId: project.id, branch: "feature/e2e-test")
        #expect(newWorkspace.branch == "feature/e2e-test")
        #expect(FileManager.default.fileExists(atPath: newWorkspace.worktreePath))

        // Step 3: Switch to the new worktree
        let session = try await orchestrator.switchWorkspace(id: newWorkspace.id)
        // Session may or may not exist yet (depends on whether one was saved)
        // The workspace should be marked active
        let updated = try store.workspace(byId: newWorkspace.id)
        #expect(updated.lastActiveAt != nil)

        // Step 4: Delete the worktree
        let wtPath = newWorkspace.worktreePath
        try await orchestrator.deleteWorkspace(id: newWorkspace.id)
        #expect(!FileManager.default.fileExists(atPath: wtPath))

        // Verify DB cleanup
        #expect(throws: (any Error).self) {
            try store.workspace(byId: newWorkspace.id)
        }

        // Main workspace should still exist
        let remainingWorkspaces = try store.workspaces(forProjectId: project.id)
        #expect(remainingWorkspaces.count >= 1)
        #expect(remainingWorkspaces.contains { $0.isMainBranch })
    }
}
