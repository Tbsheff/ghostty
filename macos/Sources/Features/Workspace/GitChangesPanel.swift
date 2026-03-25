import SwiftUI

// MARK: - Tab Selection

/// Which tab is active in the git changes panel header.
enum GitChangesPanelTab: String, CaseIterable {
    case changes = "Changes"
    case files = "Files"
}

// MARK: - GitChangesPanel

/// Right-side panel showing git status, file diffs, staging controls, and commit/push UI.
/// Designed to sit alongside the terminal in the workspace layout.
struct GitChangesPanel: View {
    /// Worktree path to query git status from.
    let worktreePath: String

    /// Called when the user wants to close the panel.
    let onClose: () -> Void

    @Environment(\.adaptiveTheme) private var theme

    @State private var selectedTab: GitChangesPanelTab = .changes
    @State private var stagedFiles: [GitFileStatus] = []
    @State private var unstagedFiles: [GitFileStatus] = []
    @State private var selectedFile: GitFileStatus?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showStaged = false
    @State private var refreshTask: Task<Void, Never>?

    private let statusManager = GitStatusManager()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            panelHeader

            // File list
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            } else if let error = errorMessage {
                DiffEmptyState(icon: "exclamationmark.triangle", message: error)
            } else {
                fileListSection

                // Diff viewer for selected file
                if selectedFile != nil {
                    Rectangle()
                        .fill(theme.borderC.opacity(0.3))
                        .frame(height: 0.5)

                    GitDiffWrapperView(
                        worktreePath: worktreePath,
                        selectedFile: selectedFile,
                        statusManager: statusManager
                    )
                    .frame(minHeight: 150)
                }

                Spacer(minLength: 0)

                // Commit section at the bottom
                Rectangle()
                    .fill(theme.borderC.opacity(0.3))
                    .frame(height: 0.5)

                CommitView(
                    worktreePath: worktreePath,
                    stagedCount: stagedFiles.count,
                    statusManager: statusManager,
                    onStatusChanged: { refreshStatus() }
                )
            }
        }
        .frame(minWidth: 280)
        .background(theme.backgroundC)
        .onAppear {
            refreshStatus()
            Task { await statusManager.startWatching(worktreePath: worktreePath) }
        }
        .onDisappear {
            refreshTask?.cancel()
            Task { await statusManager.stopWatching(worktreePath: worktreePath) }
        }
        .onChange(of: worktreePath) { _ in
            selectedFile = nil
            refreshStatus()
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 0) {
            // Segmented control
            HStack(spacing: 2) {
                ForEach(GitChangesPanelTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(2)
            .background(theme.surfaceElevatedC.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Spacer(minLength: 8)

            // File counts
            if !stagedFiles.isEmpty {
                countBadge(count: stagedFiles.count, color: theme.successC, label: "staged")
            }
            if !unstagedFiles.isEmpty {
                countBadge(count: unstagedFiles.count, color: theme.warningC, label: "changed")
            }

            Spacer(minLength: 8)

            // Refresh
            Button(action: refreshStatus) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textMutedC)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Close
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textMutedC)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AdaptiveTheme.spacing12)
        .frame(height: 36)
        .background(theme.surfaceElevatedC)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.borderC.opacity(0.3))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: GitChangesPanelTab) -> some View {
        let isSelected = selectedTab == tab
        Button(action: { selectedTab = tab }) {
            Text(tab.rawValue)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? theme.textPrimaryC : theme.textMutedC)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? theme.surfaceElevatedC : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func countBadge(count: Int, color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(theme.textMutedC)
        }
    }

    // MARK: - File List

    private var fileListSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Toggle between staged / unstaged
                HStack(spacing: 8) {
                    sectionToggle("Unstaged", count: unstagedFiles.count, isActive: !showStaged) {
                        showStaged = false
                    }
                    sectionToggle("Staged", count: stagedFiles.count, isActive: showStaged) {
                        showStaged = true
                    }
                    Spacer()
                    // Stage All button
                    if !showStaged && !unstagedFiles.isEmpty {
                        Button(action: stageAll) {
                            Text("Stage All")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(theme.accentC)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AdaptiveTheme.spacing12)
                .padding(.vertical, AdaptiveTheme.spacing8)

                // File rows
                let displayFiles = showStaged ? stagedFiles : unstagedFiles
                if displayFiles.isEmpty {
                    HStack {
                        Spacer()
                        Text(showStaged ? "No staged changes" : "No unstaged changes")
                            .font(.system(size: 12))
                            .foregroundColor(theme.textMutedC)
                            .padding(.vertical, AdaptiveTheme.spacing12)
                        Spacer()
                    }
                } else {
                    ForEach(displayFiles) { file in
                        fileRow(file)
                    }
                }
            }
        }
        .frame(maxHeight: 250)
    }

    @ViewBuilder
    private func sectionToggle(_ label: String, count: Int, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? theme.textPrimaryC : theme.textMutedC)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isActive ? theme.textPrimaryC : theme.textMutedC)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isActive ? theme.accentC.opacity(0.15) : theme.surfaceElevatedC.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func fileRow(_ file: GitFileStatus) -> some View {
        let isSelected = selectedFile?.id == file.id
        Button(action: { selectedFile = file }) {
            HStack(spacing: AdaptiveTheme.spacing8) {
                // Status icon
                statusIcon(for: file.status)

                // File path
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.fileName)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.textPrimaryC)
                        .lineLimit(1)
                    if !file.directory.isEmpty {
                        Text(file.directory)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(theme.textMutedC)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Stage/unstage toggle
                Button(action: { toggleStaging(file) }) {
                    Image(systemName: file.isStaged ? "minus.circle" : "plus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(file.isStaged ? theme.warningC : theme.successC)
                }
                .buttonStyle(.plain)
                .help(file.isStaged ? "Unstage file" : "Stage file")
            }
            .padding(.horizontal, AdaptiveTheme.spacing12)
            .padding(.vertical, AdaptiveTheme.spacing6)
            .background(isSelected ? theme.accentC.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusIcon(for status: GitFileStatusKind) -> some View {
        let (color, letter): (Color, String) = {
            switch status {
            case .modified: return (theme.warningC, "M")
            case .added: return (theme.successC, "A")
            case .deleted: return (theme.dangerC, "D")
            case .renamed: return (theme.accentC, "R")
            case .copied: return (theme.accentC, "C")
            case .untracked: return (theme.textMutedC, "?")
            }
        }()

        Text(letter)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .frame(width: 18, height: 18)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    // MARK: - Actions

    private func refreshStatus() {
        refreshTask?.cancel()
        isLoading = stagedFiles.isEmpty && unstagedFiles.isEmpty
        errorMessage = nil

        refreshTask = Task {
            do {
                let allFiles = try await statusManager.status(worktreePath: worktreePath)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    stagedFiles = allFiles.filter { $0.isStaged }
                    unstagedFiles = allFiles.filter { !$0.isStaged }
                    isLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func toggleStaging(_ file: GitFileStatus) {
        Task {
            do {
                if file.isStaged {
                    try await statusManager.unstageFile(worktreePath: worktreePath, path: file.path)
                } else {
                    try await statusManager.stageFile(worktreePath: worktreePath, path: file.path)
                }
                refreshStatus()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stageAll() {
        Task {
            do {
                try await statusManager.stageAll(worktreePath: worktreePath)
                refreshStatus()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
