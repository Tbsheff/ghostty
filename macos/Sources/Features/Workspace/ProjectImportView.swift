import SwiftUI
import GhosttyKit

// MARK: - ProjectImportView

/// Sheet for importing a git repository as a workspace project.
///
/// Flow: directory picker -> validate git repo -> show detected worktrees -> import.
/// Uses NSOpenPanel for native directory selection, validates via GitWorktreeManager,
/// and persists via WorkspaceOrchestrator.
struct ProjectImportView: View {
    let workspaceState: WorkspaceState

    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveTheme) private var theme

    @State private var selectedPath: String?
    @State private var repoName: String = ""
    @State private var detectedWorktrees: [Worktree] = []
    @State private var isValidating = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var validationState: ValidationState = .idle

    private let git = GitWorktreeManager()

    private enum ValidationState {
        case idle
        case validating
        case valid
        case invalid(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            VStack(spacing: AdaptiveTheme.spacing16) {
                directoryPicker

                if case .invalid(let message) = validationState {
                    errorBanner(message)
                }

                if !detectedWorktrees.isEmpty {
                    worktreeList
                }
            }
            .padding(AdaptiveTheme.spacing16)

            Spacer(minLength: 0)

            Divider()

            // Footer
            footer
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Repository")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.textPrimaryC)
                Text("Import a git repository to manage its worktrees")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textMutedC)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(theme.textMutedC)
            }
            .buttonStyle(.plain)
        }
        .padding(AdaptiveTheme.spacing16)
    }

    // MARK: - Directory Picker

    private var directoryPicker: some View {
        VStack(alignment: .leading, spacing: AdaptiveTheme.spacing8) {
            Text("Repository Path")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textSecondaryC)

            HStack(spacing: AdaptiveTheme.spacing8) {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textMutedC)

                    if let path = selectedPath {
                        Text(abbreviatePath(path))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(theme.textPrimaryC)
                            .lineLimit(1)
                            .truncationMode(.head)
                    } else {
                        Text("No directory selected")
                            .font(.system(size: 12))
                            .foregroundColor(theme.textMutedC)
                    }

                    Spacer()
                }
                .padding(.horizontal, AdaptiveTheme.spacing8)
                .padding(.vertical, AdaptiveTheme.spacing6)
                .background(theme.surfaceHoverC.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall)
                        .stroke(theme.borderSubtleC, lineWidth: 1)
                )

                Button("Browse...") {
                    browseForDirectory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("btn-browse")
            }
        }
    }

    // MARK: - Worktree List

    private var worktreeList: some View {
        VStack(alignment: .leading, spacing: AdaptiveTheme.spacing8) {
            HStack {
                Text("Detected Worktrees")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textSecondaryC)
                Spacer()
                Text("\(detectedWorktrees.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.textMutedC)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.surfaceHoverC)
                    .clipShape(Capsule())
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(detectedWorktrees) { wt in
                        HStack(spacing: AdaptiveTheme.spacing8) {
                            Image(systemName: wt.isMainWorktree ? "arrow.branch" : "arrow.triangle.branch")
                                .font(.system(size: 11))
                                .foregroundColor(wt.isMainWorktree ? .accentColor : theme.textMutedC)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(wt.branch ?? "detached HEAD")
                                    .font(.system(size: 12, weight: wt.isMainWorktree ? .medium : .regular))
                                    .foregroundColor(theme.textPrimaryC)

                                Text(abbreviatePath(wt.path))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(theme.textMutedC)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }

                            Spacer()

                            if wt.isMainWorktree {
                                Text("main")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, AdaptiveTheme.spacing8)
                        .padding(.vertical, AdaptiveTheme.spacing6)
                        .background(theme.surfaceHoverC.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: AdaptiveTheme.spacing8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textPrimaryC)

                Text("Select a directory that contains a .git folder")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textMutedC)
            }

            Spacer()
        }
        .padding(AdaptiveTheme.spacing10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isImporting {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
                Text("Importing...")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textMutedC)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Import") {
                performImport()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedPath == nil || detectedWorktrees.isEmpty || isImporting)
            .accessibilityIdentifier("btn-import")
            .accessibilityLabel("Import")
        }
        .padding(AdaptiveTheme.spacing16)
    }

    // MARK: - Actions

    private func browseForDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        selectedPath = path
        repoName = url.lastPathComponent
        validationState = .validating
        detectedWorktrees = []

        Task {
            await validateRepository(path: path)
        }
    }

    private func validateRepository(path: String) async {
        let isRepo = await git.isGitRepo(path)

        guard isRepo else {
            await MainActor.run {
                validationState = .invalid("Not a git repository")
                detectedWorktrees = []
            }
            return
        }

        do {
            let root = try await git.repoRoot(from: path)
            let worktrees = try await git.listWorktrees(repo: root)

            await MainActor.run {
                selectedPath = root
                repoName = (root as NSString).lastPathComponent
                detectedWorktrees = worktrees
                validationState = .valid
            }
        } catch {
            await MainActor.run {
                validationState = .invalid(error.localizedDescription)
                detectedWorktrees = []
            }
        }
    }

    private func performImport() {
        guard let path = selectedPath else { return }
        isImporting = true

        // Convert detected worktrees into RepoGroup + WorktreeStates and add to workspace
        let worktreeStates = detectedWorktrees.map { wt in
            WorktreeState(
                branch: wt.branch ?? "detached",
                worktreePath: wt.path,
                isMainBranch: wt.isMainWorktree
            )
        }

        let repo = RepoGroup(
            name: repoName,
            repoPath: path,
            worktrees: worktreeStates
        )

        workspaceState.repos.append(repo)

        // Select the main branch worktree — selectWorktree() automatically
        // creates a terminal tab via tabFactory when the worktree has no tabs.
        let targetWorktree = worktreeStates.first(where: { $0.isMainBranch }) ?? worktreeStates.first
        if let targetWorktree {
            workspaceState.selectWorktree(targetWorktree.id)
        }

        // Also persist via orchestrator in background
        Task { @MainActor in
            do {
                let store = WorkspaceStore()
                let sessionSaver = SessionAutoSaver(store: store)
                let orchestrator = WorkspaceOrchestrator(
                    store: store,
                    git: git,
                    sessionSaver: sessionSaver
                )
                _ = try await orchestrator.importProject(path: path)
            } catch {
                Ghostty.logger.warning("Failed to persist imported project: \(error.localizedDescription)")
            }
        }

        isImporting = false
        dismiss()
    }

    // MARK: - Helpers

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
