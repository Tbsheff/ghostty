import Foundation
import Testing
@testable import Ghostty

/// Integration tests for GitWorktreeManager against real temp git repos.
///
/// Each test creates a fresh temporary git repository and cleans it up in teardown.
/// These tests shell out to actual `git` commands, so they require git to be installed.
struct GitWorktreeManagerTests {
    private let manager = GitWorktreeManager()

    // MARK: - Helpers

    /// Creates a temp directory with an initialized git repo and one empty commit.
    private func makeTempRepo() throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let path = tmp.path
        try shellSync("git init \(path)")
        try shellSync("git -C \(path) config user.email test@test.com")
        try shellSync("git -C \(path) config user.name Test")
        try shellSync("git -C \(path) commit --allow-empty -m init")
        return path
    }

    /// Removes a temp directory.
    private func cleanupRepo(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Creates a non-git temp directory.
    private func makeTempDir() throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp.path
    }

    /// Synchronous shell helper for test setup.
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

    // MARK: - repoRoot

    @Test func repoRoot_validRepo_returnsRoot() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        let root = try await manager.repoRoot(from: repo)
        // Resolve symlinks for /tmp -> /private/tmp on macOS
        let resolvedRepo = (repo as NSString).resolvingSymlinksInPath
        let resolvedRoot = (root as NSString).resolvingSymlinksInPath
        #expect(resolvedRoot == resolvedRepo)
    }

    @Test func repoRoot_nonGitDir_throwsNotAGitRepo() async throws {
        let dir = try makeTempDir()
        defer { cleanupRepo(dir) }

        await #expect(throws: GitError.self) {
            try await manager.repoRoot(from: dir)
        }
    }

    // MARK: - isGitRepo

    @Test func isGitRepo_validRepo_returnsTrue() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        let result = await manager.isGitRepo(repo)
        #expect(result == true)
    }

    @Test func isGitRepo_nonGitDir_returnsFalse() async throws {
        let dir = try makeTempDir()
        defer { cleanupRepo(dir) }

        let result = await manager.isGitRepo(dir)
        #expect(result == false)
    }

    // MARK: - listWorktrees

    @Test func listWorktrees_singleWorktree_returnsMain() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        let worktrees = try await manager.listWorktrees(repo: repo)
        #expect(worktrees.count == 1)
        #expect(worktrees[0].isMainWorktree == true)
    }

    @Test func listWorktrees_multipleWorktrees_returnsAll() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        // Create a branch and add a worktree
        try shellSync("git -C \(repo) branch feature-test")
        let wtPath = repo + "-wt-feature"
        try shellSync("git -C \(repo) worktree add \(wtPath) feature-test")
        defer { cleanupRepo(wtPath) }

        let worktrees = try await manager.listWorktrees(repo: repo)
        #expect(worktrees.count == 2)
    }

    // MARK: - addWorktree

    @Test func addWorktree_newBranch_createsWorktree() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        try shellSync("git -C \(repo) branch new-feature")
        let wtPath = repo + "-wt-new-feature"
        defer { cleanupRepo(wtPath) }

        let created = try await manager.addWorktree(repo: repo, branch: "new-feature", path: wtPath)
        #expect(created.branch == "new-feature")
        #expect(FileManager.default.fileExists(atPath: wtPath))
    }

    @Test func addWorktree_existingBranch_createsWorktree() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        // Create a branch with a commit
        try shellSync("git -C \(repo) branch existing-branch")
        let wtPath = repo + "-wt-existing"
        defer { cleanupRepo(wtPath) }

        let created = try await manager.addWorktree(repo: repo, branch: "existing-branch", path: wtPath)
        #expect(FileManager.default.fileExists(atPath: wtPath))
        #expect(created.branch == "existing-branch")
    }

    @Test func addWorktree_branchAlreadyCheckedOut_throws() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        // The main branch is already checked out in the main worktree
        let currentBranch = try await manager.currentBranch(repo: repo)
        let wtPath = repo + "-wt-dup"

        await #expect(throws: GitError.self) {
            try await manager.addWorktree(repo: repo, branch: currentBranch, path: wtPath)
        }
    }

    // MARK: - removeWorktree

    @Test func removeWorktree_exists_removes() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        try shellSync("git -C \(repo) branch remove-me")
        let wtPath = repo + "-wt-remove"
        try shellSync("git -C \(repo) worktree add \(wtPath) remove-me")
        #expect(FileManager.default.fileExists(atPath: wtPath))

        try await manager.removeWorktree(repo: repo, path: wtPath)
        #expect(!FileManager.default.fileExists(atPath: wtPath))
    }

    // MARK: - listBranches

    @Test func listBranches_returnsBranches() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        try shellSync("git -C \(repo) branch branch-a")
        try shellSync("git -C \(repo) branch branch-b")

        let branches = try await manager.listBranches(repo: repo)
        let names = branches.map(\.name)
        #expect(names.contains("branch-a"))
        #expect(names.contains("branch-b"))
    }

    // MARK: - createBranch

    @Test func createBranch_newBranch_creates() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        try await manager.createBranch(repo: repo, name: "created-branch")

        let branches = try await manager.listBranches(repo: repo)
        let names = branches.map(\.name)
        #expect(names.contains("created-branch"))
    }

    // MARK: - currentBranch

    @Test func currentBranch_returnsCurrentBranch() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        let branch = try await manager.currentBranch(repo: repo)
        // git init defaults to "main" or "master"
        #expect(!branch.isEmpty)
    }

    // MARK: - diffStats

    @Test func diffStats_noChanges_returnsZero() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        let stats = try await manager.diffStats(repo: repo)
        #expect(stats.added == 0)
        #expect(stats.removed == 0)
        #expect(stats.files == 0)
    }

    @Test func diffStats_withChanges_returnsCorrectCounts() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        // Create a tracked file, commit it, then modify
        try "hello\nworld\n".write(toFile: "\(repo)/test.txt", atomically: true, encoding: .utf8)
        try shellSync("git -C \(repo) add test.txt")
        try shellSync("git -C \(repo) commit -m 'add test'")
        try "hello\nworld\nfoo\nbar\n".write(toFile: "\(repo)/test.txt", atomically: true, encoding: .utf8)

        let stats = try await manager.diffStats(repo: repo)
        #expect(stats.files >= 1)
        #expect(stats.added >= 1)
    }
}
