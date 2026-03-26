import SwiftUI

/// Thin wrapper that bridges `GitStatusManager.diff()` output to the existing `DiffPanelView` components.
///
/// Instead of modifying `DiffPanelView` (which is a self-contained diff viewer with its own
/// git runner and header), this view fetches a single-file diff from `GitStatusManager`,
/// parses it through the existing `DiffParser`, and renders it using `DiffFileSection`.
struct GitDiffWrapperView: View {
    /// Root of the worktree
    let worktreePath: String

    /// Currently selected file to diff (nil = no selection)
    let selectedFile: GitFileStatus?

    /// Shared status manager for diff operations
    let statusManager: GitStatusManager

    @Environment(\.adaptiveTheme) private var theme

    @State private var diffFiles: [DiffFile] = []
    @State private var displayMode: DiffDisplayMode = .unified
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Mini header with file name and display mode toggle
            if let file = selectedFile {
                diffHeader(file)
            }

            // Diff content
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.7)
                Spacer()
            } else if let error = errorMessage {
                DiffEmptyState(icon: "exclamationmark.triangle", message: error)
            } else if diffFiles.isEmpty {
                if selectedFile != nil {
                    DiffEmptyState(icon: "checkmark.circle", message: "No diff available")
                } else {
                    DiffEmptyState(icon: "doc.text", message: "Select a file to view diff")
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffFiles) { file in
                            DiffFileSection(file: file, displayMode: displayMode)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(theme.backgroundC)
        .onChange(of: selectedFile?.id) { _, _ in
            loadDiff()
        }
        .onAppear { loadDiff() }
        .onDisappear { loadTask?.cancel() }
    }

    // MARK: - Header

    @ViewBuilder
    private func diffHeader(_ file: GitFileStatus) -> some View {
        HStack(spacing: AdaptiveTheme.spacing8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundColor(theme.textMutedC)

            Text(file.path)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(theme.textPrimaryC)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Display mode toggle
            HStack(spacing: 2) {
                modeIcon("list.bullet", mode: .unified)
                modeIcon("rectangle.split.2x1", mode: .split)
            }
        }
        .padding(.horizontal, AdaptiveTheme.spacing12)
        .frame(height: 30)
        .background(theme.surfaceElevatedC)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.borderC.opacity(0.3))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func modeIcon(_ icon: String, mode: DiffDisplayMode) -> some View {
        let isSelected = displayMode == mode
        Button(action: { displayMode = mode }) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? theme.textPrimaryC : theme.textMutedC)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private func loadDiff() {
        loadTask?.cancel()

        guard let file = selectedFile else {
            diffFiles = []
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        loadTask = Task {
            do {
                let diffOutput = try await statusManager.diff(
                    worktreePath: worktreePath,
                    filePath: file.path,
                    staged: file.isStaged
                )

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    isLoading = false
                    if diffOutput.isEmpty {
                        diffFiles = []
                    } else {
                        diffFiles = DiffParser.parse(diffOutput)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
