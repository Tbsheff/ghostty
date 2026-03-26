import Foundation
import Testing
@testable import Ghostty

/// Integration tests for GitStatusManager against real temp git repos.
///
/// Each test creates a fresh temporary git repository with test files and
/// verifies that git status parsing, staging, and commit operations work correctly.
struct GitStatusManagerTests {
    private let manager = GitStatusManager()

    // MARK: - Helpers

    /// Creates a temp directory with an initialized git repo and one empty commit.
    private func makeTempRepo() throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-status-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let path = tmp.path
        try shellSync("git init \(path)")
        try shellSync("git -C \(path) config user.email test@test.com")
        try shellSync("git -C \(path) config user.name Test")
        try shellSync("git -C \(path) commit --allow-empty -m init")
        return path
    }

    private func cleanupRepo(_ path: String) {
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

    // MARK: - Status

    @Test func status_cleanRepo_returnsEmpty() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        // Invalidate cache to force fresh fetch
        await manager.invalidateCache(worktreePath: repo)

        let files = try await manager.status(worktreePath: repo)
        #expect(files.isEmpty)
    }

    @Test func status_modifiedFile_returnsModified() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        // Create, commit, then modify a file
        try "original".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
        try shellSync("git -C \(repo) add file.txt")
        try shellSync("git -C \(repo) commit -m 'add file'")
        try "modified".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)

        await manager.invalidateCache(worktreePath: repo)
        let files = try await manager.status(worktreePath: repo)
        let modified = files.filter { $0.status == .modified && !$0.isStaged }
        #expect(!modified.isEmpty)
        #expect(modified[0].path == "file.txt")
    }

    @Test func status_untrackedFile_returnsUntracked() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        try "new file".write(toFile: "\(repo)/untracked.txt", atomically: true, encoding: .utf8)

        await manager.invalidateCache(worktreePath: repo)
        let files = try await manager.status(worktreePath: repo)
        let untracked = files.filter { $0.status == .untracked }
        #expect(!untracked.isEmpty)
        #expect(untracked[0].path == "untracked.txt")
    }

    @Test func status_stagedFile_returnsStaged() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        try "staged content".write(toFile: "\(repo)/staged.txt", atomically: true, encoding: .utf8)
        try shellSync("git -C \(repo) add staged.txt")

        await manager.invalidateCache(worktreePath: repo)
        let files = try await manager.status(worktreePath: repo)
        let staged = files.filter { $0.isStaged }
        #expect(!staged.isEmpty)
        #expect(staged[0].status == .added)
    }

    @Test func status_renamedFile_returnsRenamed() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        // Create and commit a file, then rename it
        try "content".write(toFile: "\(repo)/old-name.txt", atomically: true, encoding: .utf8)
        try shellSync("git -C \(repo) add old-name.txt")
        try shellSync("git -C \(repo) commit -m 'add old-name'")
        try shellSync("git -C \(repo) mv old-name.txt new-name.txt")

        await manager.invalidateCache(worktreePath: repo)
        let files = try await manager.status(worktreePath: repo)
        let renamed = files.filter { $0.status == .renamed }
        #expect(!renamed.isEmpty)
    }

    @Test func status_deletedFile_returnsDeleted() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        try "doomed".write(toFile: "\(repo)/delete-me.txt", atomically: true, encoding: .utf8)
        try shellSync("git -C \(repo) add delete-me.txt")
        try shellSync("git -C \(repo) commit -m 'add delete-me'")
        try shellSync("git -C \(repo) rm delete-me.txt")

        await manager.invalidateCache(worktreePath: repo)
        let files = try await manager.status(worktreePath: repo)
        let deleted = files.filter { $0.status == .deleted }
        #expect(!deleted.isEmpty)
    }

    @Test func status_mixedChanges_returnsAll() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        // Create and commit two files
        try "a".write(toFile: "\(repo)/a.txt", atomically: true, encoding: .utf8)
        try "b".write(toFile: "\(repo)/b.txt", atomically: true, encoding: .utf8)
        try shellSync("git -C \(repo) add a.txt b.txt")
        try shellSync("git -C \(repo) commit -m 'add files'")

        // Modify one, create untracked, delete the other
        try "a-modified".write(toFile: "\(repo)/a.txt", atomically: true, encoding: .utf8)
        try shellSync("git -C \(repo) rm b.txt")
        try "new".write(toFile: "\(repo)/new.txt", atomically: true, encoding: .utf8)

        await manager.invalidateCache(worktreePath: repo)
        let files = try await manager.status(worktreePath: repo)

        let statuses = Set(files.map(\.status))
        #expect(statuses.contains(.modified))
        #expect(statuses.contains(.deleted))
        #expect(statuses.contains(.untracked))
    }

    // MARK: - Commit

    @Test func commit_withMessage_creates() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        try "commit me".write(toFile: "\(repo)/commit.txt", atomically: true, encoding: .utf8)
        try await manager.stageFile(worktreePath: repo, path: "commit.txt")
        try await manager.commit(worktreePath: repo, message: "test commit message")

        // Verify the commit was created via git log
        let log = try shellSync("git -C \(repo) log --oneline -1")
        #expect(log.contains("test commit message"))
    }

    // MARK: - Staging

    @Test func stageFile_stagesFile() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        try "stage me".write(toFile: "\(repo)/tostage.txt", atomically: true, encoding: .utf8)

        try await manager.stageFile(worktreePath: repo, path: "tostage.txt")

        await manager.invalidateCache(worktreePath: repo)
        let files = try await manager.status(worktreePath: repo)
        let staged = files.filter { $0.isStaged && $0.path == "tostage.txt" }
        #expect(!staged.isEmpty)
        #expect(staged[0].status == .added)
    }

    @Test func unstageFile_unstagesFile() async throws {
        let repo = try makeTempRepo()
        defer { cleanupRepo(repo) }

        try "unstage me".write(toFile: "\(repo)/tounstage.txt", atomically: true, encoding: .utf8)
        try shellSync("git -C \(repo) add tounstage.txt")

        // Verify it's staged
        await manager.invalidateCache(worktreePath: repo)
        var files = try await manager.status(worktreePath: repo)
        #expect(files.contains { $0.isStaged && $0.path == "tounstage.txt" })

        // Unstage
        try await manager.unstageFile(worktreePath: repo, path: "tounstage.txt")

        await manager.invalidateCache(worktreePath: repo)
        files = try await manager.status(worktreePath: repo)
        let staged = files.filter { $0.isStaged && $0.path == "tounstage.txt" }
        #expect(staged.isEmpty)

        // Should now appear as untracked
        let untracked = files.filter { $0.status == .untracked && $0.path == "tounstage.txt" }
        #expect(!untracked.isEmpty)
    }
}
