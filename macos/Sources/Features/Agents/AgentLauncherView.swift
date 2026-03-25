import SwiftUI

// MARK: - AgentLauncherView

/// Popover/sheet view for picking and launching an AI agent in the current worktree.
///
/// Shows all available agents with install status and env var warnings.
/// Designed to be presented as a popover from a toolbar button or sidebar context menu.
struct AgentLauncherView: View {
    let agents: [AgentLauncher]
    let installedCommands: Set<String>
    let missingEnvVars: [String: [String]]  // agentId -> missing var names
    let onLaunch: (AgentLauncher) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            agentList
        }
        .frame(width: 260)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Launch Agent")
                .font(.headline)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Agent List

    private var agentList: some View {
        VStack(spacing: 2) {
            ForEach(agents) { agent in
                AgentRow(
                    agent: agent,
                    isInstalled: installedCommands.contains(agent.command),
                    missingVars: missingEnvVars[agent.id] ?? [],
                    onLaunch: onLaunch
                )
            }
        }
        .padding(6)
    }
}

// MARK: - AgentRow

private struct AgentRow: View {
    let agent: AgentLauncher
    let isInstalled: Bool
    let missingVars: [String]
    let onLaunch: (AgentLauncher) -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Colored circle with icon
            ZStack {
                Circle()
                    .fill(Color(hex: agent.color))
                    .frame(width: 28, height: 28)
                Image(systemName: agent.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .opacity(isInstalled ? 1.0 : 0.4)

            // Name + subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isInstalled ? .primary : .secondary)

                if !isInstalled {
                    Text("Not installed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if !missingVars.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                        Text("Missing: \(missingVars.joined(separator: ", "))")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Launch button
            if isInstalled {
                Button("Launch") {
                    onLaunch(agent)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.00001)) // Hit target
        )
    }
}
