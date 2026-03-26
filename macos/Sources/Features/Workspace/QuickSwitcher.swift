import SwiftUI

// MARK: - QuickSwitcherItem

/// A searchable worktree entry for the quick switcher.
struct QuickSwitcherItem: Identifiable {
    let id: String          // worktreeId
    let name: String        // branch name
    let projectName: String
    let branch: String
    let lastActiveAt: Date?
}

// MARK: - QuickSwitcherView

/// Spotlight-style overlay for fuzzy-searching and switching worktrees.
///
/// Activated via Cmd+K. Shows a floating panel with a search field,
/// fuzzy-matched results, and keyboard navigation (arrows + enter + escape).
struct QuickSwitcherView: View {
    let items: [QuickSwitcherItem]
    let onSelect: (String) -> Void  // worktreeId
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [QuickSwitcherItem] {
        if query.isEmpty {
            // Recent worktrees first
            return items.sorted { a, b in
                (a.lastActiveAt ?? .distantPast) > (b.lastActiveAt ?? .distantPast)
            }
        }

        let lowercaseQuery = query.lowercased()

        // Score each item, keep only matches, sort by score descending
        return items
            .compactMap { item -> (QuickSwitcherItem, Int)? in
                let targets = [item.name, item.branch, item.projectName]
                let bestScore = targets.compactMap { fuzzyScore(query: lowercaseQuery, target: $0.lowercased()) }.max()
                guard let score = bestScore else { return nil }
                return (item, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                searchField
                Divider()
                resultsList
            }
            .frame(width: 480)
            .frame(maxHeight: 360)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .padding(.top, 80)

            // Align to top of window
            Spacer()
        }
        .onAppear { isSearchFocused = true }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Switch to worktree...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFocused)
                .onSubmit { selectCurrent() }
                .onChange(of: query) { _, _ in selectedIndex = 0 }
                .accessibilityIdentifier("quick-switcher-search")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    let results = filteredItems
                    if results.isEmpty {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            QuickSwitcherRow(
                                item: item,
                                isSelected: index == selectedIndex
                            )
                            .id(item.id)
                            .onTapGesture {
                                onSelect(item.id)
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newIndex in
                let results = filteredItems
                if newIndex >= 0, newIndex < results.count {
                    proxy.scrollTo(results[newIndex].id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Navigation

    private func moveSelection(_ delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func selectCurrent() {
        let results = filteredItems
        guard selectedIndex >= 0, selectedIndex < results.count else { return }
        onSelect(results[selectedIndex].id)
    }
}

// MARK: - QuickSwitcherRow

private struct QuickSwitcherRow: View {
    let item: QuickSwitcherItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                HStack(spacing: 6) {
                    Text(item.projectName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let lastActive = item.lastActiveAt {
                        Text(lastActive, style: .relative)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityLabel(item.name)
    }
}

// MARK: - Fuzzy Matching

/// Simple fuzzy match: checks if all query characters appear in order in the target.
/// Returns a score (higher = better) or nil if no match.
func fuzzyScore(query: String, target: String) -> Int? {
    guard !query.isEmpty else { return 0 }

    var score = 0
    var queryIndex = query.startIndex
    var targetIndex = target.startIndex
    var lastMatchIndex: String.Index?
    var consecutive = 0

    while queryIndex < query.endIndex, targetIndex < target.endIndex {
        if query[queryIndex] == target[targetIndex] {
            score += 1

            // Bonus for consecutive matches
            if let last = lastMatchIndex, target.index(after: last) == targetIndex {
                consecutive += 1
                score += consecutive * 2
            } else {
                consecutive = 0
            }

            // Bonus for match at word boundary
            if targetIndex == target.startIndex ||
               target[target.index(before: targetIndex)] == " " ||
               target[target.index(before: targetIndex)] == "/" ||
               target[target.index(before: targetIndex)] == "-" {
                score += 5
            }

            lastMatchIndex = targetIndex
            queryIndex = query.index(after: queryIndex)
        }
        targetIndex = target.index(after: targetIndex)
    }

    // All query chars must be found
    return queryIndex == query.endIndex ? score : nil
}
