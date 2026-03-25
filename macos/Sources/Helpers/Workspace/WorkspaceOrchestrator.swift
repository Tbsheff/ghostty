import Foundation

// MARK: - WorkspaceError

enum WorkspaceError: Error, LocalizedError, Sendable {
    case cannotDeleteMainBranch
    case projectNotFound(id: String)
    case workspaceNotFound(id: String)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteMainBranch:
            return "Cannot delete the main branch worktree"
        case .projectNotFound(let id):
            return "Project not found: \(id)"
        case .workspaceNotFound(let id):
            return "Workspace not found: \(id)"
        }
    }
}

// MARK: - WorkspaceOrchestrator

/// Coordinates between WorkspaceStore (persistence) and GitWorktreeManager (git CLI)
/// to manage the full lifecycle of projects and worktrees.
///
/// This is the single entry point for all workspace mutations. It ensures that
/// git operations and database records stay in sync, rolling back partial state
/// on failure.
actor WorkspaceOrchestrator {

    private let store: WorkspaceStore
    private let git: GitWorktreeManager
    private let sessionSaver: SessionAutoSaver
    private let fileManager: FileManager

    init(
        store: WorkspaceStore,
        git: GitWorktreeManager,
        sessionSaver: SessionAutoSaver,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.git = git
        self.sessionSaver = sessionSaver
        self.fileManager = fileManager
    }

    // MARK: - Import Project

    /// Imports a git repository as a project, discovering existing worktrees.
    ///
    /// If the project already exists (matched by repo root path), returns the
    /// existing record without creating duplicates.
    ///
    /// - Parameter path: Any path inside the git repository
    /// - Returns: The created or existing ProjectRecord
    func importProject(path: String) async throws -> ProjectRecord {
        let repoRoot = try await git.repoRoot(from: path)
        let repoName = (repoRoot as NSString).lastPathComponent

        // Check for existing project with same repo root
        if let existing = try await store.project(byRepoPath: repoRoot) {
            return existing
        }

        // Discover existing worktrees
        let worktrees = try await git.listWorktrees(repo: repoRoot)
        let currentBranch = try await git.currentBranch(repo: repoRoot)

        // Build workspace descriptors for the transactional import
        let workspaceDescriptors: [(branch: String, path: String, isMain: Bool)] = worktrees.map { wt in
            (
                branch: wt.branch ?? "detached",
                path: wt.path,
                isMain: wt.isMainWorktree
            )
        }

        let project = try await store.importProject(
            repoPath: repoRoot,
            name: repoName,
            worktrees: workspaceDescriptors
        )

        return project
    }

    // MARK: - Create Workspace

    /// Creates a new worktree for an existing project on the given branch.
    ///
    /// The worktree is placed at `<repoPath>/../<repoName>-worktrees/<branch>/`.
    /// If the project has a setup script, it runs in the new worktree's directory.
    /// On git failure, any partial DB record is cleaned up.
    func createWorkspace(projectId: String, branch: String) async throws -> WorkspaceRecord {
        let project = try store.project(byId: projectId)

        let worktreePath = computeWorktreePath(repoRoot: project.repoPath, branch: branch)

        // Create the worktree on disk via git
        _ = try await git.addWorktree(repo: project.repoPath, branch: branch, path: worktreePath)

        // Persist workspace record
        let workspace: WorkspaceRecord
        do {
            workspace = try await store.createWorkspace(
                projectId: projectId,
                name: branch,
                branch: branch,
                worktreePath: worktreePath,
                isMainBranch: false
            )
        } catch {
            // Rollback: remove the worktree we just created
            try? await git.removeWorktree(repo: project.repoPath, path: worktreePath, force: true)
            throw error
        }

        // Run setup script if configured (best-effort, don't fail workspace creation)
        if let setupScript = project.setupScript, !setupScript.isEmpty {
            try? await runScript(setupScript, in: worktreePath)
        }

        return workspace
    }

    // MARK: - Delete Workspace

    /// Deletes a worktree and its associated database records.
    ///
    /// The main branch worktree cannot be deleted. If a teardown script is
    /// configured, it runs before removal (errors are ignored).
    func deleteWorkspace(id: String) async throws {
        let workspace = try store.workspace(byId: id)

        guard !workspace.isMainBranch else {
            throw WorkspaceError.cannotDeleteMainBranch
        }

        let project = try store.project(byId: workspace.projectId)

        // Run teardown script if configured (ignore errors)
        if let teardownScript = project.teardownScript, !teardownScript.isEmpty {
            try? await runScript(teardownScript, in: workspace.worktreePath)
        }

        // Remove git worktree from disk
        try await git.removeWorktree(repo: project.repoPath, path: workspace.worktreePath, force: false)

        // Remove DB record (cascades to sessions)
        try await store.deleteWorkspace(id: id)
    }

    // MARK: - Switch Workspace

    /// Switches to a different workspace, saving the current session first.
    ///
    /// - Parameter id: The workspace ID to switch to
    /// - Returns: The active session for the target workspace, if one exists
    func switchWorkspace(id: String) async throws -> SessionRecord? {
        // Force-save current session before switching
        await sessionSaver.saveNow()

        // Mark the target workspace as active
        try await store.setActiveWorkspace(id: id)

        // Return the session to restore
        return try await store.activeSession(forWorkspaceId: id)
    }

    // MARK: - Restore State

    /// Restores workspace state on cold start.
    ///
    /// Validates that each active workspace's worktree path still exists on disk.
    /// Workspaces with missing paths are deactivated (the worktree was likely
    /// deleted outside the app).
    func restoreState() async throws -> [(WorkspaceRecord, SessionRecord)] {
        let activeWorkspaces = try await store.activeWorkspaces()
        var validPairs: [(WorkspaceRecord, SessionRecord)] = []

        for (workspace, session) in activeWorkspaces {
            if fileManager.fileExists(atPath: workspace.worktreePath) {
                validPairs.append((workspace, session))
            } else {
                // Worktree was removed from disk — deactivate
                try? await store.deactivateWorkspace(id: workspace.id)
            }
        }

        return validPairs
    }

    // MARK: - Private Helpers

    /// Computes the sibling worktree path for a branch.
    ///
    /// Pattern: `<repoRoot>/../<repoName>-worktrees/<sanitizedBranch>/`
    ///
    /// Branch names with `/` (e.g. `feature/auth`) are flattened to `-` to avoid
    /// nested directories.
    private func computeWorktreePath(repoRoot: String, branch: String) -> String {
        let repoName = (repoRoot as NSString).lastPathComponent
        let parentDir = (repoRoot as NSString).deletingLastPathComponent
        let sanitizedBranch = branch.replacingOccurrences(of: "/", with: "-")
        return (parentDir as NSString).appendingPathComponent(
            "\(repoName)-worktrees/\(sanitizedBranch)"
        )
    }

    /// Runs a shell script string in the given working directory.
    ///
    /// Uses `/bin/zsh -c` for execution. Throws on non-zero exit.
    private func runScript(_ script: String, in cwd: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", script]
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)

            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = FileHandle.nullDevice

            process.terminationHandler = { proc in
                if proc.terminationStatus != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: GitError.commandFailed(
                        command: "setup/teardown script",
                        stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                        exitCode: proc.terminationStatus
                    ))
                } else {
                    continuation.resume()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
