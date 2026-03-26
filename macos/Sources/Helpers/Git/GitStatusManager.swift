import Foundation

// MARK: - Supporting Types

/// Status of a single file in the git working tree or index.
enum GitFileStatusKind: String, Sendable, Equatable, CaseIterable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"

    var label: String {
        switch self {
        case .modified: return "Modified"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .copied: return "Copied"
        case .untracked: return "Untracked"
        }
    }

    var icon: String {
        switch self {
        case .modified: return "pencil"
        case .added: return "plus"
        case .deleted: return "minus"
        case .renamed: return "arrow.right"
        case .copied: return "doc.on.doc"
        case .untracked: return "questionmark"
        }
    }
}

/// Represents the status of a single file from `git status --porcelain=v2`.
struct GitFileStatus: Sendable, Equatable, Identifiable {
    var id: String { "\(isStaged ? "staged" : "unstaged")-\(path)" }

    let path: String
    let originalPath: String?
    let status: GitFileStatusKind
    let isStaged: Bool

    /// Short filename for display
    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Directory portion of the path
    var directory: String {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent().relativePath
        return dir == "." ? "" : dir
    }
}

// MARK: - Cache Entry

/// Cached git status result with a TTL.
private struct StatusCache: Sendable {
    let files: [GitFileStatus]
    let timestamp: Date
    let ttl: TimeInterval = 5.0

    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < ttl
    }
}

// MARK: - GitStatusManager Actor

/// Thread-safe actor that wraps git status, diff, staging, commit, and push operations.
///
/// Uses the same `Process`-based CLI pattern as `GitWorktreeManager`.
/// Results are cached with a 5-second TTL, invalidated by FSEvents watcher.
actor GitStatusManager {

    /// Cached status per worktree path
    private var cache: [String: StatusCache] = [:]

    /// Active FSEvents watchers per worktree path
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]

    /// File descriptors for watchers (needed for cleanup)
    private var watcherFDs: [String: Int32] = [:]

    // MARK: - Status

    /// Fetches the status of all files in the worktree. Uses cache if valid.
    func status(worktreePath: String) async throws -> [GitFileStatus] {
        if let cached = cache[worktreePath], cached.isValid {
            return cached.files
        }

        let output = try await run(["status", "--porcelain=v2"], cwd: worktreePath)
        let files = parsePorcelainV2(output)
        cache[worktreePath] = StatusCache(files: files, timestamp: Date())
        return files
    }

    /// Invalidates the cache for a worktree, forcing a fresh fetch next time.
    func invalidateCache(worktreePath: String) {
        cache.removeValue(forKey: worktreePath)
    }

    // MARK: - Diff

    /// Returns the unified diff for a specific file.
    /// - Parameters:
    ///   - worktreePath: Root of the worktree
    ///   - filePath: Relative path to the file within the worktree
    ///   - staged: If true, shows staged (--cached) diff; otherwise shows unstaged diff
    func diff(worktreePath: String, filePath: String, staged: Bool = false) async throws -> String {
        var args = ["diff", "--no-color"]
        if staged { args.append("--cached") }
        args.append("--")
        args.append(filePath)

        return try await run(args, cwd: worktreePath)
    }

    // MARK: - Staging

    /// Stages a single file.
    func stageFile(worktreePath: String, path: String) async throws {
        try await run(["add", "--", path], cwd: worktreePath)
        invalidateCache(worktreePath: worktreePath)
    }

    /// Unstages a single file (restores from index).
    func unstageFile(worktreePath: String, path: String) async throws {
        try await run(["restore", "--staged", "--", path], cwd: worktreePath)
        invalidateCache(worktreePath: worktreePath)
    }

    /// Stages all changes (tracked + untracked).
    func stageAll(worktreePath: String) async throws {
        try await run(["add", "-A"], cwd: worktreePath)
        invalidateCache(worktreePath: worktreePath)
    }

    // MARK: - Commit & Push

    /// Creates a commit with the given message.
    func commit(worktreePath: String, message: String) async throws {
        try await run(["commit", "-m", message], cwd: worktreePath)
        invalidateCache(worktreePath: worktreePath)
    }

    /// Pushes to the remote tracking branch.
    func push(worktreePath: String) async throws {
        try await run(["push"], cwd: worktreePath)
    }

    /// Pushes a new branch and sets upstream tracking.
    func pushNewBranch(worktreePath: String, branch: String) async throws {
        try await run(["push", "-u", "origin", branch], cwd: worktreePath)
    }

    // MARK: - Branch Info

    /// Returns the current branch name.
    func currentBranch(worktreePath: String) async throws -> String {
        let result = try await run(["rev-parse", "--abbrev-ref", "HEAD"], cwd: worktreePath)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks if the current branch has an upstream tracking branch.
    func hasUpstream(worktreePath: String) async -> Bool {
        do {
            _ = try await run(
                ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
                cwd: worktreePath
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - File Watching

    /// Starts an FSEvents watcher on the worktree path to invalidate cache on file changes.
    func startWatching(worktreePath: String) {
        stopWatching(worktreePath: worktreePath)

        let fd = Darwin.open(worktreePath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .link],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.invalidateCache(worktreePath: worktreePath)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        watchers[worktreePath] = source
        watcherFDs[worktreePath] = fd
    }

    /// Stops the FSEvents watcher for a worktree.
    func stopWatching(worktreePath: String) {
        watchers[worktreePath]?.cancel()
        watchers.removeValue(forKey: worktreePath)
        watcherFDs.removeValue(forKey: worktreePath)
    }

    /// Stops all watchers.
    func stopAllWatching() {
        for (_, source) in watchers {
            source.cancel()
        }
        watchers.removeAll()
        watcherFDs.removeAll()
    }

    // MARK: - Process Runner

    /// Runs a git command and returns stdout. Throws `GitError` on non-zero exit.
    @discardableResult
    private func run(_ arguments: [String], cwd: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { _ in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    if stderr.contains("not a git repository") {
                        continuation.resume(throwing: GitError.notAGitRepo)
                    } else {
                        let cmd = arguments.first ?? "unknown"
                        continuation.resume(throwing: GitError.commandFailed(
                            command: cmd,
                            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                            exitCode: process.terminationStatus
                        ))
                    }
                    return
                }
                continuation.resume(returning: stdout)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GitError.commandFailed(
                    command: arguments.first ?? "unknown",
                    stderr: error.localizedDescription,
                    exitCode: -1
                ))
            }
        }
    }

    // MARK: - Porcelain v2 Parser

    /// Parses `git status --porcelain=v2` output into `[GitFileStatus]`.
    ///
    /// Format reference:
    /// - Tracked changed: `1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>`
    /// - Renamed/copied:  `2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>\t<origPath>`
    /// - Untracked:       `? <path>`
    /// - Ignored:         `! <path>`
    ///
    /// XY encodes index (X) and worktree (Y) status:
    /// `.` = unmodified, `M` = modified, `A` = added, `D` = deleted, `R` = renamed, `C` = copied
    func parsePorcelainV2(_ output: String) -> [GitFileStatus] {
        var files: [GitFileStatus] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            guard !line.isEmpty else { continue }

            if line.hasPrefix("? ") {
                // Untracked file
                let path = String(line.dropFirst(2))
                files.append(GitFileStatus(
                    path: path,
                    originalPath: nil,
                    status: .untracked,
                    isStaged: false
                ))
            } else if line.hasPrefix("1 ") {
                // Ordinary tracked changed entry
                // Format: 1 XY sub mH mI mW hH hI path
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 9 else { continue }

                let xy = parts[1]
                guard xy.count == 2 else { continue }
                let indexChar = xy[xy.startIndex]
                let worktreeChar = xy[xy.index(after: xy.startIndex)]

                // Path is everything after the 8th space
                let pathStartIndex = nthSpaceIndex(in: line, n: 8)
                guard let pathStart = pathStartIndex else { continue }
                let path = String(line[line.index(after: pathStart)...])

                // Index (staged) status
                if indexChar != "." {
                    if let status = mapStatusChar(indexChar) {
                        files.append(GitFileStatus(
                            path: path,
                            originalPath: nil,
                            status: status,
                            isStaged: true
                        ))
                    }
                }

                // Worktree (unstaged) status
                if worktreeChar != "." {
                    if let status = mapStatusChar(worktreeChar) {
                        files.append(GitFileStatus(
                            path: path,
                            originalPath: nil,
                            status: status,
                            isStaged: false
                        ))
                    }
                }
            } else if line.hasPrefix("2 ") {
                // Renamed or copied entry
                // Format: 2 XY sub mH mI mW hH hI Xscore path\torigPath
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 10 else { continue }

                let xy = parts[1]
                guard xy.count == 2 else { continue }
                let indexChar = xy[xy.startIndex]
                let worktreeChar = xy[xy.index(after: xy.startIndex)]

                // Path and original path are tab-separated after the 9th space
                let pathStartIndex = nthSpaceIndex(in: line, n: 9)
                guard let pathStart = pathStartIndex else { continue }
                let pathPart = String(line[line.index(after: pathStart)...])
                let tabParts = pathPart.components(separatedBy: "\t")
                let path = tabParts[0]
                let origPath = tabParts.count > 1 ? tabParts[1] : nil

                // Index (staged) status
                if indexChar != "." {
                    let status: GitFileStatusKind = (indexChar == "R") ? .renamed
                        : (indexChar == "C") ? .copied
                        : mapStatusChar(indexChar) ?? .modified
                    files.append(GitFileStatus(
                        path: path,
                        originalPath: origPath,
                        status: status,
                        isStaged: true
                    ))
                }

                // Worktree (unstaged) status
                if worktreeChar != "." {
                    let status: GitFileStatusKind = (worktreeChar == "R") ? .renamed
                        : (worktreeChar == "C") ? .copied
                        : mapStatusChar(worktreeChar) ?? .modified
                    files.append(GitFileStatus(
                        path: path,
                        originalPath: origPath,
                        status: status,
                        isStaged: false
                    ))
                }
            }
            // Skip "!" (ignored) and "u" (unmerged) entries for now
        }

        return files
    }

    /// Maps a single porcelain status character to a `GitFileStatusKind`.
    private func mapStatusChar(_ c: Character) -> GitFileStatusKind? {
        switch c {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        default: return nil
        }
    }

    /// Returns the string index of the nth space in the string (1-based).
    private func nthSpaceIndex(in str: String, n: Int) -> String.Index? {
        var count = 0
        for idx in str.indices {
            if str[idx] == " " {
                count += 1
                if count == n {
                    return idx
                }
            }
        }
        return nil
    }
}
