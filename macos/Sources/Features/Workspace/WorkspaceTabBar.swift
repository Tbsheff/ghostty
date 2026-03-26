import SwiftUI
import GhosttyKit

// MARK: - WorkspaceTabBar

/// Superset-inspired two-row tab bar.
/// Row 1: Scrollable tab pills with close buttons + "+" new tab button.
/// Row 2: Agent session sub-tabs (gear for settings, sparkle for claude, etc.)
struct WorkspaceTabBar: View {
    let tabs: [WorktreeTab]
    let selectedIndex: Int
    let onSelectTab: (Int) -> Void
    let onCloseTab: (Int) -> Void
    let onNewTab: () -> Void
    let onReorderTab: (_ sourceIndex: Int, _ destinationIndex: Int) -> Void

    @State private var draggedTabId: String?
    @State private var dragOffset: CGFloat = 0
    @State private var selectedAgentSessionIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: Tab pills
            tabPillRow

            // 1px divider between rows
            Color.primary.opacity(0.08)
                .frame(height: 1)

            // Row 2: Agent session icons
            agentSessionRow
        }
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Row 1: Tab Pills

    private var tabPillRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        WorkspaceTabItem(
                            tab: tab,
                            isSelected: index == selectedIndex,
                            isDragging: draggedTabId == tab.id,
                            onSelect: { onSelectTab(index) },
                            onClose: { onCloseTab(index) },
                            onDragChanged: { value in
                                draggedTabId = tab.id
                                dragOffset = value.translation.width
                            },
                            onDragEnded: { value in
                                let averageTabWidth: CGFloat = 120
                                let indexDelta = Int(round(value.translation.width / averageTabWidth))
                                let targetIndex = max(0, min(tabs.count - 1, index + indexDelta))

                                if targetIndex != index {
                                    onReorderTab(index, targetIndex)
                                }

                                withAnimation(.easeOut(duration: 0.2)) {
                                    draggedTabId = nil
                                    dragOffset = 0
                                }
                            }
                        )
                        .zIndex(draggedTabId == tab.id ? 1 : 0)
                        .offset(x: draggedTabId == tab.id ? dragOffset : 0)
                    }
                }
                .padding(.horizontal, 4)
            }
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 1)],
                        startPoint: .leading, endPoint: .trailing
                    ).frame(width: 8)
                    Color.black
                    LinearGradient(
                        stops: [.init(color: .black, location: 0), .init(color: .clear, location: 1)],
                        startPoint: .leading, endPoint: .trailing
                    ).frame(width: 8)
                }
            )

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .padding(.trailing, AdaptiveTheme.spacing4)
        }
        .frame(height: 32)
    }

    // MARK: - Row 2: Agent Session Icons

    /// Shows sub-tab icons for the currently selected tab's agent sessions.
    /// Always shows a gear (settings) icon; agent tabs show their respective icons.
    private var agentSessionRow: some View {
        HStack(spacing: 2) {
            // Gear icon (workspace/settings session)
            AgentSessionIcon(
                icon: "gearshape.fill",
                label: "setup",
                isSelected: selectedAgentSessionIndex == 0,
                color: .secondary,
                onSelect: { selectedAgentSessionIndex = 0 }
            )

            // Agent session icons from current tab's worktree
            ForEach(Array(agentSessions.enumerated()), id: \.offset) { index, session in
                AgentSessionIcon(
                    icon: agentIcon(for: session.agentName ?? ""),
                    label: session.agentName ?? "agent",
                    isSelected: selectedAgentSessionIndex == index + 1,
                    color: agentColor(for: session.agentName ?? ""),
                    onSelect: { selectedAgentSessionIndex = index + 1 }
                )
            }

            Spacer()
        }
        .padding(.horizontal, AdaptiveTheme.spacing8)
        .frame(height: 28)
    }

    private var agentSessions: [WorktreeTab] {
        tabs.filter { $0.agentName != nil }
    }

    private func agentIcon(for name: String) -> String {
        switch name.lowercased() {
        case "claude": return "sparkle"
        case "codex": return "circle.fill"
        case "gemini": return "diamond.fill"
        default: return "circle.fill"
        }
    }

    private func agentColor(for name: String) -> Color {
        switch name.lowercased() {
        case "claude": return .purple
        case "codex": return .green
        case "gemini": return .blue
        default: return .orange
        }
    }
}

// MARK: - AgentSessionIcon

/// A small icon button for the agent session sub-tab row.
private struct AgentSessionIcon: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let color: Color
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? color : .secondary.opacity(0.5))
                    .frame(width: 24, height: 16)

                // Selection indicator line
                RoundedRectangle(cornerRadius: 1)
                    .fill(isSelected ? color : Color.clear)
                    .frame(width: 16, height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .opacity(isHovered && !isSelected ? 0.8 : 1)
    }
}

// MARK: - WorkspaceTabItem

/// Individual tab pill with close button, activity dot, and drag support.
struct WorkspaceTabItem: View {
    let tab: WorktreeTab
    let isSelected: Bool
    let isDragging: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDragChanged: ((DragGesture.Value) -> Void)?
    let onDragEnded: ((DragGesture.Value) -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: AdaptiveTheme.spacing4) {
            // Agent indicator dot
            if let agentName = tab.agentName {
                Circle()
                    .fill(agentColor(for: agentName))
                    .frame(width: 7, height: 7)
            } else if tab.tabColor != .none, let displayColor = tab.tabColor.displayColor {
                Circle()
                    .fill(Color(nsColor: displayColor))
                    .frame(width: 7, height: 7)
            }

            Text(tab.title)
                .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isSelected ? .primary : .secondary)

            // Activity indicator (filled circle when tab has unseen changes)
            if tab.agentName != nil {
                Circle()
                    .fill(Color.primary.opacity(0.4))
                    .frame(width: 5, height: 5)
            }

            // Close button (visible on hover)
            ZStack {
                WorkspaceTabCloseButton(action: onClose)
                    .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(.horizontal, AdaptiveTheme.spacing8)
        .padding(.vertical, AdaptiveTheme.spacing4)
        .background(tabBackground)
        .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in onDragChanged?(value) }
                .onEnded { value in onDragEnded?(value) }
        )
        .onHover { isHovered = $0 }
        .scaleEffect(isDragging ? 1.05 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.15 : 0), radius: isDragging ? 4 : 0)
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }

    @ViewBuilder
    private var tabBackground: some View {
        if isSelected {
            Color.primary.opacity(0.15)
        } else if isHovered {
            Color.primary.opacity(0.07)
        } else {
            Color.clear
        }
    }

    private func agentColor(for name: String) -> Color {
        switch name.lowercased() {
        case "claude": return .purple
        case "codex": return .green
        case "gemini": return .blue
        default: return .orange
        }
    }
}

// MARK: - WorkspaceTabCloseButton

struct WorkspaceTabCloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(isHovered ? .primary : .secondary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .frame(width: 14, height: 14)
        .background(
            Circle()
                .fill(Color.primary.opacity(isHovered ? 0.12 : 0))
        )
        .onHover { isHovered = $0 }
    }
}
