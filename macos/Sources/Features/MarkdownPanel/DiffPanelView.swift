import SwiftUI
import AppKit

// MARK: - Diff Data Model

/// Represents a single line in a diff
struct DiffLine: Identifiable {
    let id = UUID()
    let type: LineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    enum LineType {
        case added
        case removed
        case context
        case hunkHeader
    }
}

/// Represents a hunk (section) of changes
struct DiffHunk: Identifiable {
    let id = UUID()
    let header: String
    let lines: [DiffLine]
}

/// Represents a single file's diff
struct DiffFile: Identifiable {
    let id = UUID()
    let oldPath: String
    let newPath: String
    let hunks: [DiffHunk]

    var displayPath: String {
        // Use new path for renames, otherwise just the path
        if oldPath == newPath || oldPath == "/dev/null" {
            return newPath
        }
        return "\(oldPath) → \(newPath)"
    }

    var fileName: String {
        URL(fileURLWithPath: newPath).lastPathComponent
    }
}

// MARK: - Diff Parser

/// Parses unified diff format output from `git diff`
enum DiffParser {
    static func parse(_ input: String) -> [DiffFile] {
        let lines = input.components(separatedBy: "\n")
        var files: [DiffFile] = []
        var currentOldPath: String?
        var currentNewPath: String?
        var currentHunks: [DiffHunk] = []
        var currentHunkHeader: String?
        var currentHunkLines: [DiffLine] = []
        var oldLineNum = 0
        var newLineNum = 0

        func flushHunk() {
            if let header = currentHunkHeader, !currentHunkLines.isEmpty {
                currentHunks.append(DiffHunk(header: header, lines: currentHunkLines))
            }
            currentHunkHeader = nil
            currentHunkLines = []
        }

        func flushFile() {
            flushHunk()
            if let oldPath = currentOldPath, let newPath = currentNewPath {
                files.append(DiffFile(oldPath: oldPath, newPath: newPath, hunks: currentHunks))
            }
            currentOldPath = nil
            currentNewPath = nil
            currentHunks = []
        }

        for line in lines {
            if line.hasPrefix("diff --git") {
                flushFile()
                continue
            }

            if line.hasPrefix("--- a/") {
                currentOldPath = String(line.dropFirst(6))
                continue
            }
            if line.hasPrefix("--- /dev/null") {
                currentOldPath = "/dev/null"
                continue
            }

            if line.hasPrefix("+++ b/") {
                currentNewPath = String(line.dropFirst(6))
                continue
            }
            if line.hasPrefix("+++ /dev/null") {
                currentNewPath = "/dev/null"
                continue
            }

            // Skip index/mode lines
            if line.hasPrefix("index ") || line.hasPrefix("old mode") || line.hasPrefix("new mode") ||
               line.hasPrefix("new file") || line.hasPrefix("deleted file") || line.hasPrefix("similarity") ||
               line.hasPrefix("rename from") || line.hasPrefix("rename to") || line.hasPrefix("Binary") {
                continue
            }

            if line.hasPrefix("@@") {
                flushHunk()
                currentHunkHeader = line

                // Parse line numbers from @@ -old,count +new,count @@
                let parts = line.components(separatedBy: " ")
                if parts.count >= 3 {
                    let oldPart = parts[1] // -old,count
                    let newPart = parts[2] // +new,count
                    oldLineNum = abs(Int(oldPart.components(separatedBy: ",").first?.dropFirst() ?? "1") ?? 1)
                    newLineNum = abs(Int(newPart.components(separatedBy: ",").first?.dropFirst() ?? "1") ?? 1)
                }
                continue
            }

            // Only parse content lines if we're inside a hunk
            guard currentHunkHeader != nil else { continue }

            if line.hasPrefix("+") {
                currentHunkLines.append(DiffLine(
                    type: .added,
                    content: String(line.dropFirst()),
                    oldLineNumber: nil,
                    newLineNumber: newLineNum
                ))
                newLineNum += 1
            } else if line.hasPrefix("-") {
                currentHunkLines.append(DiffLine(
                    type: .removed,
                    content: String(line.dropFirst()),
                    oldLineNumber: oldLineNum,
                    newLineNumber: nil
                ))
                oldLineNum += 1
            } else if line.hasPrefix(" ") {
                currentHunkLines.append(DiffLine(
                    type: .context,
                    content: String(line.dropFirst()),
                    oldLineNumber: oldLineNum,
                    newLineNumber: newLineNum
                ))
                oldLineNum += 1
                newLineNum += 1
            } else if line.isEmpty && currentHunkHeader != nil {
                // Empty line within a hunk is treated as context
                currentHunkLines.append(DiffLine(
                    type: .context,
                    content: "",
                    oldLineNumber: oldLineNum,
                    newLineNumber: newLineNum
                ))
                oldLineNum += 1
                newLineNum += 1
            }
        }

        flushFile()
        return files
    }
}

// MARK: - Git Diff Runner

/// Runs `git diff` in a given directory
enum GitDiffRunner {
    static func run(in directory: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["diff", "--no-color"]
                process.currentDirectoryURL = URL(fileURLWithPath: directory)
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Run `git diff --staged` for staged changes
    static func runStaged(in directory: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["diff", "--staged", "--no-color"]
                process.currentDirectoryURL = URL(fileURLWithPath: directory)
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Diff Display Mode

enum DiffDisplayMode: String, CaseIterable {
    case unified = "Unified"
    case split = "Split"
}

// MARK: - Diff Scope

enum DiffScope: String, CaseIterable {
    case unstaged = "Unstaged"
    case staged = "Staged"
}

// MARK: - Diff Panel View

/// Main diff panel view with header and diff content
struct DiffPanelView: View {
    let cwd: String
    let onClose: () -> Void

    @Environment(\.adaptiveTheme) private var theme
    @State private var files: [DiffFile] = []
    @State private var isLoading = false
    @State private var displayMode: DiffDisplayMode = .unified
    @State private var diffScope: DiffScope = .unstaged
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DiffPanelHeader(
                displayMode: $displayMode,
                diffScope: $diffScope,
                onRefresh: loadDiff,
                onClose: onClose
            )

            // Content
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            } else if let error = errorMessage {
                DiffEmptyState(icon: "exclamationmark.triangle", message: error)
            } else if files.isEmpty {
                DiffEmptyState(icon: "checkmark.circle", message: "No changes")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(files) { file in
                            DiffFileSection(file: file, displayMode: displayMode)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 280)
        .background(theme.backgroundC)
        .onAppear { loadDiff() }
        .onChange(of: cwd) { _ in loadDiff() }
        .onChange(of: diffScope) { _ in loadDiff() }
    }

    private func loadDiff() {
        guard !cwd.isEmpty else {
            errorMessage = "No working directory"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            let output: String?
            switch diffScope {
            case .unstaged:
                output = await GitDiffRunner.run(in: cwd)
            case .staged:
                output = await GitDiffRunner.runStaged(in: cwd)
            }

            await MainActor.run {
                isLoading = false
                if let output, !output.isEmpty {
                    files = DiffParser.parse(output)
                    if files.isEmpty {
                        errorMessage = nil // No error, just no changes
                    }
                } else {
                    files = []
                }
            }
        }
    }
}

// MARK: - Diff Panel Header

struct DiffPanelHeader: View {
    @Binding var displayMode: DiffDisplayMode
    @Binding var diffScope: DiffScope
    let onRefresh: () -> Void
    let onClose: () -> Void

    @Environment(\.adaptiveTheme) private var theme
    @State private var refreshHovered = false
    @State private var closeHovered = false

    var body: some View {
        HStack(spacing: AdaptiveTheme.spacing8) {
            // Diff scope picker
            Picker("", selection: $diffScope) {
                ForEach(DiffScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)

            Spacer()

            // Display mode toggle
            Picker("", selection: $displayMode) {
                ForEach(DiffDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 130)

            // Refresh
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(refreshHovered ? theme.iconHover : theme.iconDefault))
                    .frame(width: 28, height: 28)
                    .background(refreshHovered ? theme.surfaceHoverC : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
            }
            .buttonStyle(.plain)
            .help("Refresh diff")
            .onHover { refreshHovered = $0 }

            // Close
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(closeHovered ? theme.iconHover : theme.iconDefault))
                    .frame(width: 28, height: 28)
                    .background(closeHovered ? theme.surfaceHoverC : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
            }
            .buttonStyle(.plain)
            .help("Close")
            .onHover { closeHovered = $0 }
        }
        .padding(.horizontal, AdaptiveTheme.spacing12)
        .padding(.vertical, AdaptiveTheme.spacing8)
        .background(theme.surfaceElevatedC)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.borderC.opacity(0.3))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Diff File Section

struct DiffFileSection: View {
    let file: DiffFile
    let displayMode: DiffDisplayMode

    @Environment(\.adaptiveTheme) private var theme
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            Button(action: { withAnimation(.easeOut(duration: AdaptiveTheme.animationFast)) { isExpanded.toggle() } }) {
                HStack(spacing: AdaptiveTheme.spacing6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textMutedC)
                        .frame(width: 14)

                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondaryC)

                    Text(file.displayPath)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.textPrimaryC)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    // Stats
                    HStack(spacing: AdaptiveTheme.spacing4) {
                        let stats = fileStats
                        if stats.additions > 0 {
                            Text("+\(stats.additions)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(theme.successC)
                        }
                        if stats.deletions > 0 {
                            Text("-\(stats.deletions)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(theme.dangerC)
                        }
                    }
                }
                .padding(.horizontal, AdaptiveTheme.spacing12)
                .padding(.vertical, AdaptiveTheme.spacing8)
                .background(theme.surfaceElevatedC)
            }
            .buttonStyle(.plain)

            if isExpanded {
                switch displayMode {
                case .unified:
                    UnifiedDiffView(file: file)
                case .split:
                    SplitDiffView(file: file)
                }
            }
        }
    }

    private var fileStats: (additions: Int, deletions: Int) {
        var additions = 0
        var deletions = 0
        for hunk in file.hunks {
            for line in hunk.lines {
                switch line.type {
                case .added: additions += 1
                case .removed: deletions += 1
                default: break
                }
            }
        }
        return (additions, deletions)
    }
}

// MARK: - Unified Diff View

struct UnifiedDiffView: View {
    let file: DiffFile

    @Environment(\.adaptiveTheme) private var theme

    private let lineNumberWidth: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(file.hunks) { hunk in
                // Hunk header
                Text(hunk.header)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textMutedC)
                    .padding(.horizontal, AdaptiveTheme.spacing12)
                    .padding(.vertical, AdaptiveTheme.spacing4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.accentC.opacity(0.08))

                // Lines
                ForEach(hunk.lines) { line in
                    HStack(spacing: 0) {
                        // Old line number
                        Text(line.oldLineNumber.map { String($0) } ?? "")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.textMutedC)
                            .frame(width: lineNumberWidth, alignment: .trailing)
                            .padding(.trailing, 4)

                        // New line number
                        Text(line.newLineNumber.map { String($0) } ?? "")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.textMutedC)
                            .frame(width: lineNumberWidth, alignment: .trailing)
                            .padding(.trailing, 4)

                        // Indicator
                        Text(lineIndicator(line.type))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(lineIndicatorColor(line.type))
                            .frame(width: 16)

                        // Content
                        Text(line.content)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(lineTextColor(line.type))
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.vertical, 1)
                    .background(lineBackground(line.type))
                }
            }
        }
    }

    private func lineIndicator(_ type: DiffLine.LineType) -> String {
        switch type {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        case .hunkHeader: return "@"
        }
    }

    private func lineIndicatorColor(_ type: DiffLine.LineType) -> Color {
        switch type {
        case .added: return theme.successC
        case .removed: return theme.dangerC
        default: return theme.textMutedC
        }
    }

    private func lineTextColor(_ type: DiffLine.LineType) -> Color {
        switch type {
        case .added: return theme.textPrimaryC
        case .removed: return theme.textPrimaryC
        case .context: return theme.textSecondaryC
        case .hunkHeader: return theme.textMutedC
        }
    }

    private func lineBackground(_ type: DiffLine.LineType) -> Color {
        switch type {
        case .added: return theme.successC.opacity(0.1)
        case .removed: return theme.dangerC.opacity(0.1)
        default: return Color.clear
        }
    }
}

// MARK: - Split Diff View

struct SplitDiffView: View {
    let file: DiffFile

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(file.hunks) { hunk in
                // Hunk header spanning both sides
                Text(hunk.header)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textMutedC)
                    .padding(.horizontal, AdaptiveTheme.spacing12)
                    .padding(.vertical, AdaptiveTheme.spacing4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.accentC.opacity(0.08))

                // Paired lines
                ForEach(Array(pairedLines(hunk.lines).enumerated()), id: \.offset) { _, pair in
                    HStack(spacing: 0) {
                        // Left side (old)
                        splitLineView(pair.old, side: .old)

                        // Divider
                        Rectangle()
                            .fill(theme.borderC)
                            .frame(width: 1)

                        // Right side (new)
                        splitLineView(pair.new, side: .new)
                    }
                }
            }
        }
    }

    private enum Side { case old, new }

    @ViewBuilder
    private func splitLineView(_ line: DiffLine?, side: Side) -> some View {
        HStack(spacing: 0) {
            // Line number
            let num = side == .old ? line?.oldLineNumber : line?.newLineNumber
            Text(num.flatMap { String($0) } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.textMutedC)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 4)

            // Content
            if let line {
                Text(line.content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(lineTextColor(line.type))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity)
        .background(line.map { lineBackground($0.type) } ?? Color.clear)
    }

    private func lineTextColor(_ type: DiffLine.LineType) -> Color {
        switch type {
        case .added: return theme.textPrimaryC
        case .removed: return theme.textPrimaryC
        case .context: return theme.textSecondaryC
        case .hunkHeader: return theme.textMutedC
        }
    }

    private func lineBackground(_ type: DiffLine.LineType) -> Color {
        switch type {
        case .added: return theme.successC.opacity(0.1)
        case .removed: return theme.dangerC.opacity(0.1)
        default: return Color.clear
        }
    }

    /// Pair removed and added lines for side-by-side display
    private func pairedLines(_ lines: [DiffLine]) -> [(old: DiffLine?, new: DiffLine?)] {
        var result: [(DiffLine?, DiffLine?)] = []
        var removals: [DiffLine] = []
        var additions: [DiffLine] = []

        func flushPairs() {
            let count = max(removals.count, additions.count)
            for i in 0..<count {
                let old = i < removals.count ? removals[i] : nil
                let new = i < additions.count ? additions[i] : nil
                result.append((old, new))
            }
            removals.removeAll()
            additions.removeAll()
        }

        for line in lines {
            switch line.type {
            case .removed:
                removals.append(line)
            case .added:
                additions.append(line)
            case .context:
                flushPairs()
                result.append((line, line))
            case .hunkHeader:
                flushPairs()
            }
        }

        flushPairs()
        return result
    }
}

// MARK: - Empty State

struct DiffEmptyState: View {
    let icon: String
    let message: String

    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        VStack(spacing: AdaptiveTheme.spacing12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(theme.textMutedC)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondaryC)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
