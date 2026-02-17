import SwiftUI
import AppKit

// MARK: - Diff Data Model

/// Represents a single line in a diff
struct DiffLine: Identifiable {
    /// Stable ID from position + type for SwiftUI diffing
    var id: String { "\(oldLineNumber ?? 0)-\(newLineNumber ?? 0)-\(type)" }
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
    var id: String { header }
    let header: String
    let lines: [DiffLine]
}

/// Represents a single file's diff
struct DiffFile: Identifiable {
    var id: String { "\(oldPath)-\(newPath)" }
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

// MARK: - Pill Toggle

/// Custom sliding pill toggle — replaces stock segmented control with animated indicator
struct PillToggle<T: Hashable & CaseIterable & RawRepresentable>: View
    where T.RawValue == String, T.AllCases: RandomAccessCollection {

    @Binding var selection: T
    @Namespace private var pillAnimation
    @Environment(\.adaptiveTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(T.allCases, id: \.self) { option in
                pillOption(option)
            }
        }
        .padding(2)
        .background(theme.backgroundC.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium)
                .stroke(theme.borderSubtleC.opacity(0.5), lineWidth: 1)
        )
        .fixedSize()
    }

    @ViewBuilder
    private func pillOption(_ option: T) -> some View {
        let isSelected = selection == option
        Text(option.rawValue)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isSelected ? theme.textPrimaryC : theme.textMutedC)
            .padding(.horizontal, AdaptiveTheme.spacing10)
            .padding(.vertical, 4)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall)
                            .fill(theme.surfaceHoverC)
                            .matchedGeometryEffect(id: "pill", in: pillAnimation)
                    }
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: AdaptiveTheme.springResponse,
                                      dampingFraction: AdaptiveTheme.springDamping)) {
                    selection = option
                }
            }
    }
}

// MARK: - Mode Button

/// Icon + text button for display mode selection with accent-tinted active state
struct DiffModeButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.adaptiveTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, AdaptiveTheme.spacing8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var foregroundColor: Color {
        if isSelected { return theme.accentC }
        if isHovered { return theme.textSecondaryC }
        return theme.textMutedC
    }

    private var backgroundColor: Color {
        if isSelected && isHovered { return theme.accentC.opacity(0.18) }
        if isSelected { return theme.accentC.opacity(0.12) }
        if isHovered { return theme.surfaceHoverC.opacity(0.5) }
        return Color.clear
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
        VStack(spacing: 0) {
            // Row 1: Scope + Actions
            HStack(spacing: AdaptiveTheme.spacing8) {
                PillToggle(selection: $diffScope)

                Spacer()

                HStack(spacing: 2) {
                    headerIconButton(
                        icon: "arrow.clockwise",
                        size: 11,
                        isHovered: $refreshHovered,
                        help: "Refresh diff",
                        action: onRefresh
                    )
                    headerIconButton(
                        icon: "xmark",
                        size: 10,
                        weight: .semibold,
                        isHovered: $closeHovered,
                        help: "Close",
                        action: onClose
                    )
                }
            }
            .padding(.horizontal, AdaptiveTheme.spacing12)
            .padding(.vertical, AdaptiveTheme.spacing8)

            // Row 2: Display Mode
            HStack(spacing: AdaptiveTheme.spacing4) {
                DiffModeButton(
                    icon: "list.bullet",
                    label: "Unified",
                    isSelected: displayMode == .unified,
                    action: { displayMode = .unified }
                )
                DiffModeButton(
                    icon: "rectangle.split.2x1",
                    label: "Split",
                    isSelected: displayMode == .split,
                    action: { displayMode = .split }
                )

                Spacer()
            }
            .padding(.horizontal, AdaptiveTheme.spacing12)
            .padding(.vertical, AdaptiveTheme.spacing6)
            .background(theme.backgroundC.opacity(0.3))
        }
        .background(theme.surfaceElevatedC)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.borderC.opacity(0.3))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func headerIconButton(
        icon: String,
        size: CGFloat,
        weight: Font.Weight = .medium,
        isHovered: Binding<Bool>,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: weight))
                .foregroundColor(Color(isHovered.wrappedValue ? theme.iconHover : theme.iconDefault))
                .frame(width: 26, height: 26)
                .background(isHovered.wrappedValue ? theme.surfaceHoverC : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered.wrappedValue = $0 }
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
            // File header — Codex layout: [icon] [path] [+N] [-N] ... [chevron]
            Button(action: { withAnimation(.easeOut(duration: AdaptiveTheme.animationFast)) { isExpanded.toggle() } }) {
                HStack(spacing: AdaptiveTheme.spacing6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondaryC)

                    Text(file.displayPath)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.textPrimaryC)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    // Inline colored stats
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

                    Spacer()

                    // Right-side chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textMutedC)
                        .frame(width: 14)
                }
                .padding(.horizontal, AdaptiveTheme.spacing12)
                .padding(.vertical, AdaptiveTheme.spacing8)
                .background(theme.surfaceElevatedC)
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Bottom border when expanded
                Rectangle()
                    .fill(theme.borderC.opacity(0.2))
                    .frame(height: 0.5)

                if file.hunks.isEmpty {
                    // Binary or empty file
                    Text("Binary file changed")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(theme.textMutedC)
                        .padding(AdaptiveTheme.spacing12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    switch displayMode {
                    case .unified:
                        UnifiedDiffView(file: file)
                    case .split:
                        SplitDiffView(file: file)
                    }
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var expandedContextSections: Set<String> = []

    private let edgeBarWidth: CGFloat = 3
    private let lineNumberWidth: CGFloat = 44

    private var language: String? { languageFromPath(file.newPath) }
    private var markdownTheme: MarkdownTheme { MarkdownTheme(colorScheme: colorScheme) }

    var body: some View {
        let rows = buildDisplayRows(from: file)
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                switch row {
                case .line(let line):
                    unifiedLineRow(line)
                case .collapsedContext(let lines, let stableId):
                    if expandedContextSections.contains(stableId) {
                        ForEach(lines) { line in
                            unifiedLineRow(line)
                        }
                    } else {
                        collapsedContextRow(count: lines.count, stableId: stableId)
                    }
                case .hunkSeparator(_, let hiddenCount):
                    hunkSeparatorRow(hiddenCount: hiddenCount)
                }
            }
        }
    }

    // MARK: - Line Row

    @ViewBuilder
    private func unifiedLineRow(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            // 3px colored edge bar
            Rectangle()
                .fill(edgeColor(line.type))
                .frame(width: edgeBarWidth)

            // Single line number
            let num = line.type == .removed ? line.oldLineNumber : line.newLineNumber
            Text(num.map { String($0) } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.textMutedC)
                .frame(width: lineNumberWidth, alignment: .trailing)
                .padding(.trailing, 8)

            // Syntax-highlighted content
            Text(highlightLine(line.content, language: language, theme: markdownTheme))
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 3)
        .background(lineBackground(line.type))
    }

    // MARK: - Collapsed Context Row

    @ViewBuilder
    private func collapsedContextRow(count: Int, stableId: String) -> some View {
        Button(action: { expandedContextSections.insert(stableId) }) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: edgeBarWidth)

                Image(systemName: "suit.diamond")
                    .font(.system(size: 8))
                    .foregroundColor(theme.textMutedC)
                    .padding(.leading, AdaptiveTheme.spacing8)

                Text("\(count) unmodified lines")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textMutedC)
                    .padding(.leading, AdaptiveTheme.spacing6)

                Spacer()
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(theme.surfaceElevatedC.opacity(0.3))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hunk Separator

    @ViewBuilder
    private func hunkSeparatorRow(hiddenCount: Int) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: edgeBarWidth)

            Text("···")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.textMutedC)
                .padding(.leading, AdaptiveTheme.spacing8)

            if hiddenCount > 0 {
                Text("\(hiddenCount) lines between changes")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textMutedC)
                    .padding(.leading, AdaptiveTheme.spacing6)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(theme.surfaceElevatedC.opacity(0.15))
    }

    // MARK: - Colors

    private func edgeColor(_ type: DiffLine.LineType) -> Color {
        switch type {
        case .added: return theme.successC
        case .removed: return theme.dangerC
        default: return Color.clear
        }
    }

    private func lineBackground(_ type: DiffLine.LineType) -> Color {
        switch type {
        case .added: return theme.successC.opacity(0.08)
        case .removed: return theme.dangerC.opacity(0.08)
        default: return Color.clear
        }
    }
}

// MARK: - Split Diff View

struct SplitDiffView: View {
    let file: DiffFile

    @Environment(\.adaptiveTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var expandedContextSections: Set<String> = []

    private let edgeBarWidth: CGFloat = 3
    private let lineNumberWidth: CGFloat = 36

    private var language: String? { languageFromPath(file.newPath) }
    private var markdownTheme: MarkdownTheme { MarkdownTheme(colorScheme: colorScheme) }

    private enum Side { case old, new }

    var body: some View {
        let rows = buildSplitDisplayRows(from: file)
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                switch row {
                case .pair(let old, let new, _):
                    splitPairRow(old: old, new: new)
                case .collapsedContext(let lines, let stableId):
                    if expandedContextSections.contains(stableId) {
                        ForEach(lines) { line in
                            splitPairRow(old: line, new: line)
                        }
                    } else {
                        splitCollapsedRow(count: lines.count, stableId: stableId)
                    }
                case .hunkSeparator(_, let hiddenCount):
                    splitHunkSeparator(hiddenCount: hiddenCount)
                }
            }
        }
    }

    // MARK: - Pair Row

    @ViewBuilder
    private func splitPairRow(old: DiffLine?, new: DiffLine?) -> some View {
        HStack(spacing: 0) {
            splitSideView(old, side: .old)

            Rectangle()
                .fill(theme.borderC.opacity(0.5))
                .frame(width: 1)

            splitSideView(new, side: .new)
        }
    }

    @ViewBuilder
    private func splitSideView(_ line: DiffLine?, side: Side) -> some View {
        HStack(spacing: 0) {
            // Edge bar
            Rectangle()
                .fill(line.map { splitEdgeColor($0.type, side: side) } ?? Color.clear)
                .frame(width: edgeBarWidth)

            // Line number
            let num = side == .old ? line?.oldLineNumber : line?.newLineNumber
            Text(num.flatMap { String($0) } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.textMutedC)
                .frame(width: lineNumberWidth, alignment: .trailing)
                .padding(.trailing, 8)

            // Syntax-highlighted content
            if let line {
                Text(highlightLine(line.content, language: language, theme: markdownTheme))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(line.map { splitBackground($0.type, side: side) } ?? Color.clear)
    }

    // MARK: - Collapsed Context (spans full width)

    @ViewBuilder
    private func splitCollapsedRow(count: Int, stableId: String) -> some View {
        Button(action: { expandedContextSections.insert(stableId) }) {
            HStack(spacing: 0) {
                Image(systemName: "suit.diamond")
                    .font(.system(size: 8))
                    .foregroundColor(theme.textMutedC)
                    .padding(.leading, AdaptiveTheme.spacing8)

                Text("\(count) unmodified lines")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textMutedC)
                    .padding(.leading, AdaptiveTheme.spacing6)

                Spacer()
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(theme.surfaceElevatedC.opacity(0.3))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hunk Separator

    @ViewBuilder
    private func splitHunkSeparator(hiddenCount: Int) -> some View {
        HStack(spacing: 0) {
            Text("···")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.textMutedC)
                .padding(.leading, AdaptiveTheme.spacing8)

            if hiddenCount > 0 {
                Text("\(hiddenCount) lines between changes")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textMutedC)
                    .padding(.leading, AdaptiveTheme.spacing6)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(theme.surfaceElevatedC.opacity(0.15))
    }

    // MARK: - Colors

    private func splitEdgeColor(_ type: DiffLine.LineType, side: Side) -> Color {
        switch type {
        case .removed where side == .old: return theme.dangerC
        case .added where side == .new: return theme.successC
        default: return Color.clear
        }
    }

    private func splitBackground(_ type: DiffLine.LineType, side: Side) -> Color {
        switch type {
        case .removed where side == .old: return theme.dangerC.opacity(0.08)
        case .added where side == .new: return theme.successC.opacity(0.08)
        default: return Color.clear
        }
    }
}

// MARK: - Display Row Types

/// Represents a single row in the flattened diff display
private enum DiffDisplayRow: Identifiable {
    case line(DiffLine)
    case collapsedContext(lines: [DiffLine], stableId: String)
    case hunkSeparator(stableId: String, hiddenCount: Int)

    var id: String {
        switch self {
        case .line(let l): return l.id
        case .collapsedContext(_, let sid): return "collapse-\(sid)"
        case .hunkSeparator(let sid, _): return "hunksep-\(sid)"
        }
    }
}

/// Represents a paired row in split diff display
private enum SplitDisplayRow: Identifiable {
    case pair(old: DiffLine?, new: DiffLine?, stableId: String)
    case collapsedContext(lines: [DiffLine], stableId: String)
    case hunkSeparator(stableId: String, hiddenCount: Int)

    var id: String {
        switch self {
        case .pair(_, _, let sid): return "pair-\(sid)"
        case .collapsedContext(_, let sid): return "collapse-\(sid)"
        case .hunkSeparator(let sid, _): return "hunksep-\(sid)"
        }
    }
}

// MARK: - Diff Helpers

/// Collapse threshold: runs of context lines > this get collapsed
private let collapseThreshold = 6

/// Build a flat list of display rows from all hunks, inserting inter-hunk separators
private func buildDisplayRows(from file: DiffFile) -> [DiffDisplayRow] {
    var rows: [DiffDisplayRow] = []

    for (hunkIdx, hunk) in file.hunks.enumerated() {
        // Inter-hunk separator
        if hunkIdx > 0 {
            let prevHunk = file.hunks[hunkIdx - 1]
            let prevLastNew = prevHunk.lines.last?.newLineNumber ?? 0
            let currFirstNew = hunk.lines.first?.newLineNumber ?? 0
            let gap = max(0, currFirstNew - prevLastNew - 1)
            rows.append(.hunkSeparator(
                stableId: "hunksep-\(hunkIdx)",
                hiddenCount: gap
            ))
        }

        // Process lines within this hunk
        var contextRun: [DiffLine] = []
        var contextRunStart = 0

        func flushContext() {
            guard !contextRun.isEmpty else { return }
            if contextRun.count <= collapseThreshold {
                for line in contextRun { rows.append(.line(line)) }
            } else {
                // Show first 3, collapse middle, show last 3
                for line in contextRun.prefix(3) { rows.append(.line(line)) }
                let middle = Array(contextRun.dropFirst(3).dropLast(3))
                if !middle.isEmpty {
                    let sid = "ctx-\(hunkIdx)-\(contextRunStart)"
                    rows.append(.collapsedContext(lines: middle, stableId: sid))
                }
                for line in contextRun.suffix(3) { rows.append(.line(line)) }
            }
            contextRun = []
        }

        for (lineIdx, line) in hunk.lines.enumerated() {
            if line.type == .context {
                if contextRun.isEmpty { contextRunStart = lineIdx }
                contextRun.append(line)
            } else {
                flushContext()
                if line.type != .hunkHeader {
                    rows.append(.line(line))
                }
            }
        }
        flushContext()
    }

    return rows
}

/// Build split display rows from all hunks
private func buildSplitDisplayRows(from file: DiffFile) -> [SplitDisplayRow] {
    var rows: [SplitDisplayRow] = []

    for (hunkIdx, hunk) in file.hunks.enumerated() {
        // Inter-hunk separator
        if hunkIdx > 0 {
            let prevHunk = file.hunks[hunkIdx - 1]
            let prevLastNew = prevHunk.lines.last?.newLineNumber ?? 0
            let currFirstNew = hunk.lines.first?.newLineNumber ?? 0
            let gap = max(0, currFirstNew - prevLastNew - 1)
            rows.append(.hunkSeparator(
                stableId: "hunksep-\(hunkIdx)",
                hiddenCount: gap
            ))
        }

        // Pair lines first
        let paired = pairedLines(hunk.lines)

        // Group context pairs and apply collapsing
        var contextRun: [(old: DiffLine?, new: DiffLine?)] = []
        var contextRunStart = 0

        func flushContext() {
            guard !contextRun.isEmpty else { return }
            // Extract DiffLines for the collapsed section
            let contextLines = contextRun.compactMap { $0.old ?? $0.new }
            if contextRun.count <= collapseThreshold {
                for (i, pair) in contextRun.enumerated() {
                    let sid = "\(hunkIdx)-ctx-\(contextRunStart + i)"
                    rows.append(.pair(old: pair.old, new: pair.new, stableId: sid))
                }
            } else {
                // Show first 3
                for (i, pair) in contextRun.prefix(3).enumerated() {
                    let sid = "\(hunkIdx)-ctx-\(contextRunStart + i)"
                    rows.append(.pair(old: pair.old, new: pair.new, stableId: sid))
                }
                // Collapse middle
                let middleLines = Array(contextLines.dropFirst(3).dropLast(3))
                if !middleLines.isEmpty {
                    let sid = "ctx-\(hunkIdx)-\(contextRunStart)"
                    rows.append(.collapsedContext(lines: middleLines, stableId: sid))
                }
                // Show last 3
                let lastThree = contextRun.suffix(3)
                for (i, pair) in lastThree.enumerated() {
                    let sid = "\(hunkIdx)-ctx-\(contextRunStart + contextRun.count - 3 + i)"
                    rows.append(.pair(old: pair.old, new: pair.new, stableId: sid))
                }
            }
            contextRun = []
        }

        for (pairIdx, pair) in paired.enumerated() {
            let isContext = (pair.old?.type == .context || pair.new?.type == .context)
                && pair.old?.type != .added && pair.old?.type != .removed
                && pair.new?.type != .added && pair.new?.type != .removed
            if isContext {
                if contextRun.isEmpty { contextRunStart = pairIdx }
                contextRun.append(pair)
            } else {
                flushContext()
                let sid = "\(hunkIdx)-\(pairIdx)"
                rows.append(.pair(old: pair.old, new: pair.new, stableId: sid))
            }
        }
        flushContext()
    }

    return rows
}

/// Pair removed and added lines for side-by-side display (shared helper)
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
        case .removed: removals.append(line)
        case .added: additions.append(line)
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

/// Map file extension to language string for SyntaxHighlighter
private func languageFromPath(_ path: String) -> String? {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    switch ext {
    case "swift": return "swift"
    case "py": return "python"
    case "js", "jsx", "mjs", "cjs": return "javascript"
    case "ts", "tsx", "mts": return "typescript"
    case "go": return "go"
    case "rs": return "rust"
    case "zig": return "zig"
    case "c", "h": return "c"
    case "cpp", "cxx", "cc", "hpp", "hxx": return "cpp"
    case "rb": return "ruby"
    case "java": return "java"
    case "kt", "kts": return "kotlin"
    case "sql": return "sql"
    case "sh", "bash", "zsh": return "shell"
    case "json": return "json"
    case "yaml", "yml": return "yaml"
    case "toml": return "toml"
    case "css": return "css"
    case "html", "htm": return "html"
    default: return nil
    }
}

/// Syntax-highlight a single line, overriding font size to 12pt for diff typography
private func highlightLine(_ content: String, language: String?, theme: MarkdownTheme) -> AttributedString {
    guard let language, !content.trimmingCharacters(in: .whitespaces).isEmpty else {
        var attr = AttributedString(content)
        attr.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        return attr
    }
    var result = SyntaxHighlighter.highlight(content, language: language, theme: theme)
    // Override font size from codeFontSize to 12pt while keeping syntax colors
    var modified = AttributedString()
    for run in result.runs {
        var slice = result[run.range]
        let isBold = run.font?.fontDescriptor.symbolicTraits.contains(.bold) == true
        slice.font = .monospacedSystemFont(ofSize: 12, weight: isBold ? .bold : .regular)
        modified.append(AttributedString(slice))
    }
    return modified
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
