import SwiftUI

/// Commit and push section embedded at the bottom of GitChangesPanel.
/// Provides a multi-line commit message editor, commit button, and push/publish button.
struct CommitView: View {
    /// Worktree path for git operations
    let worktreePath: String

    /// Number of currently staged files (drives commit button state)
    let stagedCount: Int

    /// Shared status manager for commit/push operations
    let statusManager: GitStatusManager

    /// Called after a successful commit or push so the parent can refresh
    let onStatusChanged: () -> Void

    @Environment(\.adaptiveTheme) private var theme

    @State private var commitMessage: String = ""
    @State private var isCommitting = false
    @State private var isPushing = false
    @State private var hasUpstream = true
    @State private var currentBranch = ""
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var feedbackDismissTask: Task<Void, Never>?

    private var canCommit: Bool {
        !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && stagedCount > 0
            && !isCommitting
    }

    var body: some View {
        VStack(spacing: 0) {
            // Commit message editor
            commitEditor

            // Action buttons
            actionButtons

            // Feedback
            if let feedback = feedbackMessage {
                feedbackBanner(feedback, isError: feedbackIsError)
            }
        }
        .padding(AdaptiveTheme.spacing12)
        .background(theme.surfaceElevatedC)
        .onAppear { checkBranchInfo() }
        .onChange(of: worktreePath) { _, _ in checkBranchInfo() }
    }

    // MARK: - Commit Editor

    private var commitEditor: some View {
        VStack(alignment: .leading, spacing: AdaptiveTheme.spacing6) {
            HStack {
                Text("Commit")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.textSecondaryC)
                Spacer()
                if stagedCount > 0 {
                    Text("\(stagedCount) staged")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.successC)
                }
            }

            ZStack(alignment: .topLeading) {
                if commitMessage.isEmpty {
                    Text("Commit message...")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(theme.textMutedC)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $commitMessage)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(theme.textPrimaryC)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 48, maxHeight: 100)
            }
            .background(theme.surfaceElevatedC)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(theme.borderSubtleC, lineWidth: 1)
            )

            // Character count
            HStack {
                Spacer()
                Text("\(commitMessage.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(commitMessage.count > 72 ? theme.warningC : theme.textMutedC)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: AdaptiveTheme.spacing8) {
            // Commit button
            Button(action: performCommit) {
                HStack(spacing: 4) {
                    if isCommitting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }
                    Text("Commit")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(canCommit ? theme.accentC : theme.surfaceElevatedC)
                .foregroundColor(canCommit ? .white : theme.textMutedC)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)

            // Push / Publish Branch button
            Button(action: performPush) {
                HStack(spacing: 4) {
                    if isPushing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }
                    Text(hasUpstream ? "Push" : "Publish Branch")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(theme.surfaceElevatedC)
                .foregroundColor(isPushing ? theme.textMutedC : theme.textPrimaryC)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(theme.borderSubtleC, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isPushing)
        }
        .padding(.top, AdaptiveTheme.spacing8)
    }

    // MARK: - Feedback Banner

    @ViewBuilder
    private func feedbackBanner(_ message: String, isError: Bool) -> some View {
        HStack(spacing: AdaptiveTheme.spacing6) {
            Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.system(size: 11))
                .foregroundColor(isError ? theme.dangerC : theme.successC)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(isError ? theme.dangerC : theme.successC)
                .lineLimit(2)
            Spacer()
        }
        .padding(.top, AdaptiveTheme.spacing8)
        .transition(.opacity)
    }

    // MARK: - Actions

    private func performCommit() {
        guard canCommit else { return }
        isCommitting = true
        clearFeedback()

        Task {
            do {
                try await statusManager.commit(
                    worktreePath: worktreePath,
                    message: commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await MainActor.run {
                    commitMessage = ""
                    isCommitting = false
                    showFeedback("Committed successfully", isError: false)
                    onStatusChanged()
                }
            } catch {
                await MainActor.run {
                    isCommitting = false
                    showFeedback(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func performPush() {
        isPushing = true
        clearFeedback()

        Task {
            do {
                if hasUpstream {
                    try await statusManager.push(worktreePath: worktreePath)
                } else {
                    try await statusManager.pushNewBranch(
                        worktreePath: worktreePath,
                        branch: currentBranch
                    )
                    await MainActor.run { hasUpstream = true }
                }
                await MainActor.run {
                    isPushing = false
                    showFeedback("Pushed successfully", isError: false)
                }
            } catch {
                await MainActor.run {
                    isPushing = false
                    showFeedback(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func checkBranchInfo() {
        Task {
            let upstream = await statusManager.hasUpstream(worktreePath: worktreePath)
            let branch = (try? await statusManager.currentBranch(worktreePath: worktreePath)) ?? ""
            await MainActor.run {
                hasUpstream = upstream
                currentBranch = branch
            }
        }
    }

    private func showFeedback(_ message: String, isError: Bool) {
        feedbackDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            feedbackMessage = message
            feedbackIsError = isError
        }
        feedbackDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    feedbackMessage = nil
                }
            }
        }
    }

    private func clearFeedback() {
        feedbackDismissTask?.cancel()
        feedbackMessage = nil
    }
}
