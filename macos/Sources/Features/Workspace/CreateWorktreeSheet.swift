import SwiftUI
import GhosttyKit

// MARK: - CreateWorktreeSheet

/// Sheet for creating a new git worktree within a repository.
///
/// Allows selecting an existing branch or creating a new one,
/// previews the computed worktree path, and creates via GitWorktreeManager.
struct CreateWorktreeSheet: View {
    let workspaceState: WorkspaceState
    let repo: RepoGroup

    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveTheme) private var theme

    @State private var branchName = ""
    @State private var createNewBranch = true
    @State private var selectedExistingBranch: String?
    @State private var availableBranches: [Branch] = []
    @State private var isLoadingBranches = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    private let git = GitWorktreeManager()

    private var effectiveBranch: String {
        createNewBranch ? branchName : (selectedExistingBranch ?? "")
    }

    private var computedWorktreePath: String {
        guard !effectiveBranch.isEmpty else { return "" }
        let repoName = (repo.repoPath as NSString).lastPathComponent
        let parentDir = (repo.repoPath as NSString).deletingLastPathComponent
        let sanitized = effectiveBranch.replacingOccurrences(of: "/", with: "-")
        return (parentDir as NSString).appendingPathComponent("\(repoName)-worktrees/\(sanitized)")
    }

    private var isValidBranchName: Bool {
        guard !effectiveBranch.isEmpty else { return false }
        // Basic git ref validation: no spaces, no .., no ~, no ^, no :, no \, no [
        let invalidChars = CharacterSet(charactersIn: " ..~^:\\[]@{}")
        return effectiveBranch.rangeOfCharacter(from: invalidChars) == nil
            && !effectiveBranch.hasPrefix("-")
            && !effectiveBranch.hasSuffix(".")
            && !effectiveBranch.hasSuffix(".lock")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: AdaptiveTheme.spacing16) {
                branchModeToggle
                branchInput

                if !computedWorktreePath.isEmpty {
                    pathPreview
                }

                if let error = errorMessage {
                    errorBanner(error)
                }
            }
            .padding(AdaptiveTheme.spacing16)

            Spacer(minLength: 0)

            Divider()

            footer
        }
        .frame(width: 440, height: 360)
        .task {
            await loadBranches()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Worktree")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.textPrimaryC)
                Text("Create a new worktree for \(repo.name)")
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

    // MARK: - Branch Mode Toggle

    private var branchModeToggle: some View {
        Picker("", selection: $createNewBranch) {
            Text("New Branch").tag(true)
            Text("Existing Branch").tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Branch Input

    @ViewBuilder
    private var branchInput: some View {
        if createNewBranch {
            VStack(alignment: .leading, spacing: AdaptiveTheme.spacing4) {
                Text("Branch Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textSecondaryC)

                TextField("feature/my-branch", text: $branchName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .accessibilityIdentifier("branch-name-field")

                if !branchName.isEmpty && !isValidBranchName {
                    Text("Invalid branch name")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: AdaptiveTheme.spacing4) {
                Text("Select Branch")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textSecondaryC)

                if isLoadingBranches {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading branches...")
                            .font(.system(size: 12))
                            .foregroundColor(theme.textMutedC)
                    }
                } else if availableBranches.isEmpty {
                    Text("No available branches found")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textMutedC)
                } else {
                    branchPicker
                }
            }
        }
    }

    private var branchPicker: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 1) {
                ForEach(unusedBranches) { branch in
                    Button {
                        selectedExistingBranch = branch.name
                    } label: {
                        HStack(spacing: AdaptiveTheme.spacing6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 11))
                                .foregroundColor(
                                    selectedExistingBranch == branch.name
                                        ? .accentColor : theme.textMutedC
                                )
                                .frame(width: 16)

                            Text(branch.name)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(theme.textPrimaryC)
                                .lineLimit(1)

                            Spacer()

                            if selectedExistingBranch == branch.name {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, AdaptiveTheme.spacing8)
                        .padding(.vertical, AdaptiveTheme.spacing4)
                        .background(
                            selectedExistingBranch == branch.name
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 120)
        .background(theme.surfaceHoverC.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall)
                .stroke(theme.borderSubtleC, lineWidth: 1)
        )
    }

    /// Branches not already used by a worktree in this repo.
    private var unusedBranches: [Branch] {
        let usedBranches = Set(repo.worktrees.map(\.branch))
        return availableBranches.filter { !usedBranches.contains($0.name) && !$0.isRemote }
    }

    // MARK: - Path Preview

    private var pathPreview: some View {
        VStack(alignment: .leading, spacing: AdaptiveTheme.spacing4) {
            Text("Worktree Path")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textSecondaryC)

            HStack(spacing: AdaptiveTheme.spacing6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textMutedC)

                Text(abbreviatePath(computedWorktreePath))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textMutedC)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, AdaptiveTheme.spacing8)
            .padding(.vertical, AdaptiveTheme.spacing6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surfaceHoverC.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: AdaptiveTheme.spacing8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(theme.textPrimaryC)

            Spacer()
        }
        .padding(AdaptiveTheme.spacing10)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isCreating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
                Text("Creating worktree...")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textMutedC)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Create") {
                performCreate()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isValidBranchName || effectiveBranch.isEmpty || isCreating)
            .accessibilityIdentifier("btn-create-worktree")
            .accessibilityLabel("Create")
        }
        .padding(AdaptiveTheme.spacing16)
    }

    // MARK: - Actions

    private func loadBranches() async {
        isLoadingBranches = true
        defer { isLoadingBranches = false }

        do {
            let branches = try await git.listBranches(repo: repo.repoPath)
            await MainActor.run {
                availableBranches = branches
            }
        } catch {
            Ghostty.logger.warning("Failed to load branches: \(error.localizedDescription)")
        }
    }

    private func performCreate() {
        guard isValidBranchName else { return }
        isCreating = true
        errorMessage = nil

        Task {
            do {
                // If creating a new branch, create it first
                if createNewBranch {
                    try await git.createBranch(repo: repo.repoPath, name: branchName)
                }

                // Create the git worktree
                let worktree = try await git.addWorktree(
                    repo: repo.repoPath,
                    branch: effectiveBranch,
                    path: computedWorktreePath
                )

                // Add to workspace state on main thread
                await MainActor.run {
                    let worktreeState = WorktreeState(
                        branch: worktree.branch ?? effectiveBranch,
                        worktreePath: worktree.path,
                        isMainBranch: false
                    )
                    repo.worktrees.append(worktreeState)
                    // selectWorktree() automatically posts .workspaceWorktreeNeedsTab
                    // when the worktree has no tabs.
                    workspaceState.selectWorktree(worktreeState.id)

                    isCreating = false
                    dismiss()
                }

                // Persist to DB in background (best-effort)
                await persistWorktree(branch: effectiveBranch)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }

    @MainActor
    private func persistWorktree(branch: String) async {
        let store = WorkspaceStore()
        let sessionSaver = SessionAutoSaver(store: store)
        let orchestrator = WorkspaceOrchestrator(
            store: store,
            git: git,
            sessionSaver: sessionSaver
        )
        if let project = try? store.project(byRepoPath: repo.repoPath) {
            _ = try? await orchestrator.createWorkspace(
                projectId: project.id,
                branch: branch
            )
        }
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
