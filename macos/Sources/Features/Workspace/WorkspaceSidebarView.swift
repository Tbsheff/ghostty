import SwiftUI
import GhosttyKit

// MARK: - WorkspaceSidebarView

/// Superset-inspired sidebar with navigation header, repo groups with letter avatars,
/// and two-line worktree rows showing status dot, display name, diff stats, branch, and ticket.
struct WorkspaceSidebarView: View {
    let workspaceState: WorkspaceState

    @State private var searchText = ""
    @State private var showImportSheet = false
    @State private var createWorktreeRepo: RepoGroup?

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        SidebarContainer(identifier: "workspace.sidebar") {
            VStack(spacing: 0) {
                // Navigation header
                sidebarNavigationHeader
                    .padding(.horizontal, AdaptiveTheme.spacing10)
                    .padding(.top, AdaptiveTheme.spacing10)
                    .padding(.bottom, AdaptiveTheme.spacing6)

                // New Workspace button
                newWorkspaceButton
                    .padding(.horizontal, AdaptiveTheme.spacing10)
                    .padding(.bottom, AdaptiveTheme.spacing8)

                SidebarDivider()

                // Repo list or empty state
                if filteredRepos.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            ForEach(filteredRepos) { repo in
                                repoSection(repo)
                            }
                        }
                        .padding(.bottom, AdaptiveTheme.spacing8)
                    }
                }

                Spacer(minLength: 0)

                SidebarDivider()

                // Add Repository button
                addRepositoryButton
                    .padding(.horizontal, AdaptiveTheme.spacing10)
                    .padding(.vertical, AdaptiveTheme.spacing8)
            }
        }
        .accessibilityIdentifier("workspace-sidebar")
        .sheet(isPresented: $showImportSheet) {
            ProjectImportView(workspaceState: workspaceState)
        }
        .sheet(item: $createWorktreeRepo) { repo in
            CreateWorktreeSheet(
                workspaceState: workspaceState,
                repo: repo
            )
        }
    }

    // MARK: - Navigation Header

    @State private var selectedNav: SidebarNav = .workspaces

    private enum SidebarNav {
        case workspaces, tasks
    }

    private var sidebarNavigationHeader: some View {
        HStack(spacing: AdaptiveTheme.spacing4) {
            navButton("Workspaces", nav: .workspaces)
            navButton("Tasks", nav: .tasks)
            Spacer()
        }
    }

    private func navButton(_ title: String, nav: SidebarNav) -> some View {
        Button {
            selectedNav = nav
        } label: {
            Text(title)
                .font(.system(size: 12, weight: selectedNav == nav ? .bold : .regular))
                .foregroundColor(selectedNav == nav ? theme.textPrimaryC : theme.textMutedC)
                .padding(.horizontal, AdaptiveTheme.spacing6)
                .padding(.vertical, AdaptiveTheme.spacing4)
                .background(
                    selectedNav == nav
                        ? theme.surfaceHoverC.opacity(0.6)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("nav-\(title.lowercased())")
    }

    // MARK: - New Workspace Button

    @State private var newWorkspaceHovered = false

    private var newWorkspaceButton: some View {
        Button {
            if let firstRepo = displayRepos.first(where: { !$0.repoPath.isEmpty }) {
                createWorktreeRepo = firstRepo
            } else {
                showImportSheet = true
            }
        } label: {
            HStack(spacing: AdaptiveTheme.spacing6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                Text("New Workspace")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(newWorkspaceHovered ? theme.textPrimaryC : theme.textSecondaryC)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AdaptiveTheme.spacing6)
            .background(
                RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous)
                    .strokeBorder(
                        newWorkspaceHovered ? theme.textMutedC : theme.borderSubtleC,
                        lineWidth: 1
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous)
                    .fill(newWorkspaceHovered ? theme.surfaceHoverC.opacity(0.4) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { newWorkspaceHovered = $0 }
        .animation(.linear(duration: AdaptiveTheme.animationFast), value: newWorkspaceHovered)
        .accessibilityLabel("New Workspace")
        .accessibilityIdentifier("btn-new-workspace")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AdaptiveTheme.spacing10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(theme.textMutedC)

            VStack(spacing: AdaptiveTheme.spacing4) {
                Text("No repositories")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textSecondaryC)

                Text("Import a git repository to manage\nworktrees and agent sessions")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textMutedC)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button {
                showImportSheet = true
            } label: {
                Text("Import Repository")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, AdaptiveTheme.spacing10)
                    .padding(.vertical, AdaptiveTheme.spacing6)
                    .background(
                        RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous)
                            .fill(Color.accentColor.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, AdaptiveTheme.spacing4)
        }
        .padding(.horizontal, AdaptiveTheme.spacing16)
    }

    // MARK: - Filtered Data

    /// Repos to display. Hides the default "Terminal" placeholder repo once real repos exist.
    private var displayRepos: [RepoGroup] {
        let realRepos = workspaceState.repos.filter { !$0.repoPath.isEmpty }
        // If we have real repos, only show those; otherwise show all (including default)
        return realRepos.isEmpty ? workspaceState.repos : realRepos
    }

    private var filteredRepos: [RepoGroup] {
        guard !searchText.isEmpty else { return displayRepos }
        return displayRepos.compactMap { repo in
            let matchingWorktrees = repo.worktrees.filter {
                $0.branch.localizedCaseInsensitiveContains(searchText)
            }
            guard !matchingWorktrees.isEmpty else { return nil }
            return repo
        }
    }

    private func filteredWorktrees(for repo: RepoGroup) -> [WorktreeState] {
        guard !searchText.isEmpty else { return repo.worktrees }
        return repo.worktrees.filter {
            $0.branch.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Repo Section

    @ViewBuilder
    private func repoSection(_ repo: RepoGroup) -> some View {
        // Repo header: avatar + name (count) + "+" button + chevron
        RepoGroupHeader(
            repo: repo,
            onToggle: {
                withAnimation(.spring(response: AdaptiveTheme.springResponse, dampingFraction: AdaptiveTheme.springDamping)) {
                    repo.isExpanded.toggle()
                }
            },
            onAddWorktree: { createWorktreeRepo = repo }
        )

        if repo.isExpanded {
            ForEach(filteredWorktrees(for: repo)) { worktree in
                SupersetWorktreeRow(
                    worktree: worktree,
                    isSelected: workspaceState.selectedWorktreeId == worktree.id,
                    onSelect: { workspaceState.selectWorktree(worktree.id) }
                )
                .contextMenu {
                    worktreeContextMenu(worktree: worktree, repo: repo)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func worktreeContextMenu(worktree: WorktreeState, repo: RepoGroup) -> some View {
        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.worktreePath)
        } label: {
            Label("Open in Finder", systemImage: "folder")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worktree.worktreePath, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        Divider()

        Button {
            launchAgent(worktree: worktree, agentName: "claude")
        } label: {
            Label("Launch Claude", systemImage: "sparkle")
        }

        Divider()

        Button(role: .destructive) {
            deleteWorktree(worktree: worktree, repo: repo)
        } label: {
            Label("Delete Worktree", systemImage: "trash")
        }
        .disabled(worktree.isMainBranch)
    }

    // MARK: - Add Repository Button

    @State private var addRepoHovered = false

    private var addRepositoryButton: some View {
        Button {
            showImportSheet = true
        } label: {
            HStack(spacing: AdaptiveTheme.spacing6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                Text("Add repository")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundColor(addRepoHovered ? theme.textSecondaryC : theme.textMutedC)
            .padding(.vertical, AdaptiveTheme.spacing6)
            .padding(.horizontal, AdaptiveTheme.spacing6)
            .background(
                RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous)
                    .fill(addRepoHovered ? theme.surfaceHoverC : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { addRepoHovered = $0 }
        .animation(.linear(duration: AdaptiveTheme.animationFast), value: addRepoHovered)
        .accessibilityLabel("Add repository")
        .accessibilityIdentifier("btn-add-repository")
    }

    // MARK: - Actions

    private func launchAgent(worktree: WorktreeState, agentName: String) {
        NotificationCenter.default.post(
            name: .workspaceLaunchAgent,
            object: nil,
            userInfo: [
                "worktreeId": worktree.id,
                "agentName": agentName,
            ]
        )
    }

    private func deleteWorktree(worktree: WorktreeState, repo: RepoGroup) {
        NotificationCenter.default.post(
            name: .workspaceDeleteWorktree,
            object: nil,
            userInfo: [
                "worktreeId": worktree.id,
                "repoPath": repo.repoPath,
            ]
        )
    }
}

// MARK: - Repo Group Header

/// Superset-style repo group header with colored letter avatar, name (count),
/// add button, and expandable chevron.
private struct RepoGroupHeader: View {
    let repo: RepoGroup
    let onToggle: () -> Void
    let onAddWorktree: () -> Void

    @Environment(\.adaptiveTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AdaptiveTheme.spacing6) {
                // Colored letter avatar
                Text(repo.avatarLetter)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(repo.avatarColor)
                    )

                // Repo name + worktree count
                Text("\(repo.name)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.textPrimaryC)
                    .lineLimit(1)

                Text("(\(repo.worktrees.count))")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(theme.textMutedC)

                Spacer()

                // Add worktree button
                Button(action: onAddWorktree) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textMutedC)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add worktree to \(repo.name)")

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.textMutedC)
                    .rotationEffect(.degrees(repo.isExpanded ? 90 : 0))
                    .accessibilityLabel(repo.isExpanded ? "Collapse" : "Expand")
            }
            .padding(.horizontal, AdaptiveTheme.spacing10)
            .padding(.vertical, AdaptiveTheme.spacing6)
            .background(isHovered ? theme.surfaceHoverC : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("repo-group-\(repo.name)")
        .accessibilityLabel("\(repo.name), \(repo.worktrees.count) worktrees")
    }
}

// MARK: - SupersetWorktreeRow

/// Two-line worktree row matching Superset layout:
/// Line 1: [status dot]  Worktree Name        +1932 -128
/// Line 2:               branch/name    arrow #4562
private struct SupersetWorktreeRow: View {
    let worktree: WorktreeState
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.adaptiveTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: AdaptiveTheme.spacing8) {
                // Status dot
                statusDot
                    .padding(.top, 5)

                // Two-line content
                VStack(alignment: .leading, spacing: 2) {
                    // Line 1: display name + diff stats
                    HStack(spacing: 0) {
                        Text(worktree.resolvedDisplayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isSelected ? theme.textPrimaryC : theme.textSecondaryC)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: AdaptiveTheme.spacing4)

                        // Diff stats (green +N, red -N)
                        if let stats = worktree.diffStats, (stats.added > 0 || stats.removed > 0) {
                            diffStatsView(stats)
                        }
                    }

                    // Line 2: branch name + ticket reference
                    HStack(spacing: 0) {
                        Text(worktree.branch)
                            .font(.system(size: 11))
                            .foregroundColor(theme.textMutedC)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: AdaptiveTheme.spacing4)

                        // Ticket reference with arrows icon
                        if let ticket = worktree.ticketReference, !ticket.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(theme.textMutedC)
                                Text(ticket)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(theme.textMutedC)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AdaptiveTheme.spacing10)
            .padding(.leading, AdaptiveTheme.spacing16) // indent under repo header
            .padding(.vertical, AdaptiveTheme.spacing6)
            .frame(height: 44)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.linear(duration: AdaptiveTheme.animationFast), value: isHovered)
        .animation(.linear(duration: AdaptiveTheme.animationFast), value: isSelected)
        .accessibilityIdentifier("worktree-\(worktree.branch)")
        .accessibilityLabel(worktree.branch)
        .accessibilityHint("Double tap to select worktree")
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch worktree.status {
        case .idle: return Color(red: 0.35, green: 0.55, blue: 0.95) // Superset blue
        case .activeAgent: return Color(red: 0.3, green: 0.85, blue: 0.5) // Superset green
        case .running: return Color(red: 0.95, green: 0.6, blue: 0.2) // Superset orange
        }
    }

    // MARK: - Row Background

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            theme.selectionActiveC
        } else if isHovered {
            theme.surfaceHoverC
        } else {
            Color.clear
        }
    }

    // MARK: - Diff Stats

    private func diffStatsView(_ stats: DiffStats) -> some View {
        HStack(spacing: AdaptiveTheme.spacing4) {
            if stats.added > 0 {
                Text("+\(stats.added)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.green.opacity(0.85))
            }
            if stats.removed > 0 {
                Text("-\(stats.removed)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.red.opacity(0.85))
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let workspaceLaunchAgent = Notification.Name("com.ghostty.workspace.launchAgent")
    static let workspaceDeleteWorktree = Notification.Name("com.ghostty.workspace.deleteWorktree")
    static let workspaceWorktreeNeedsTab = Notification.Name("com.ghostty.workspace.worktreeNeedsTab")
}
