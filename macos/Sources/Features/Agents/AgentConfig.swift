import Foundation
import GRDB

// MARK: - AgentLauncher

/// Describes an AI agent that can be launched in a worktree terminal tab.
struct AgentLauncher: Identifiable, Sendable {
    let id: String
    let name: String
    let command: String
    let args: [String]
    let icon: String       // SF Symbol name
    let color: String      // Hex color string
    let requiredEnvVars: [String]

    init(
        id: String = UUID().uuidString,
        name: String,
        command: String,
        args: [String] = [],
        icon: String,
        color: String,
        requiredEnvVars: [String] = []
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.icon = icon
        self.color = color
        self.requiredEnvVars = requiredEnvVars
    }
}

// MARK: - Built-in Presets

extension AgentLauncher {
    static let builtInPresets: [AgentLauncher] = [
        AgentLauncher(
            id: "builtin-claude",
            name: "Claude Code",
            command: "claude",
            icon: "brain.head.profile",
            color: "#D97706",
            requiredEnvVars: ["ANTHROPIC_API_KEY"]
        ),
        AgentLauncher(
            id: "builtin-codex",
            name: "Codex",
            command: "codex",
            icon: "terminal",
            color: "#10B981",
            requiredEnvVars: ["OPENAI_API_KEY"]
        ),
        AgentLauncher(
            id: "builtin-gemini",
            name: "Gemini",
            command: "gemini",
            icon: "sparkles",
            color: "#3B82F6",
            requiredEnvVars: ["GEMINI_API_KEY"]
        ),
        AgentLauncher(
            id: "builtin-aider",
            name: "Aider",
            command: "aider",
            icon: "bubble.left.and.text.bubble.right",
            color: "#8B5CF6"
        ),
    ]
}

// MARK: - AgentConfigManager

/// Manages the set of available agent launchers, merging built-in presets
/// with per-project overrides stored in the database.
final class AgentConfigManager: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    /// Returns agents available for a project, merging built-in presets with
    /// any per-project overrides from the database.
    ///
    /// DB records whose `command` matches a built-in preset override that preset's
    /// fields. Records with no matching built-in are appended as custom agents.
    func availableAgents(forProjectId projectId: String?) -> [AgentLauncher] {
        var agents = AgentLauncher.builtInPresets

        guard let projectId else { return agents }

        let dbLaunchers: [AgentLauncherRecord]
        do {
            dbLaunchers = try dbPool.read { db in
                try AgentLauncherRecord
                    .filter(AgentLauncherRecord.Columns.projectId == projectId)
                    .order(AgentLauncherRecord.Columns.sortOrder)
                    .fetchAll(db)
            }
        } catch {
            return agents
        }

        for record in dbLaunchers {
            if let index = agents.firstIndex(where: { $0.command == record.command }) {
                // Override built-in with DB values
                agents[index] = AgentLauncher(
                    id: record.id,
                    name: record.name,
                    command: record.command,
                    args: record.decodedArgs,
                    icon: record.icon ?? agents[index].icon,
                    color: record.color ?? agents[index].color
                )
            } else {
                // Custom agent from DB
                agents.append(AgentLauncher(
                    id: record.id,
                    name: record.name,
                    command: record.command,
                    args: record.decodedArgs,
                    icon: record.icon ?? "terminal",
                    color: record.color ?? "#6B7280"
                ))
            }
        }

        return agents
    }

    /// Checks `which <command>` for each built-in + project agent,
    /// returning only those whose CLI binary is found on PATH.
    func detectInstalledAgents() async -> [AgentLauncher] {
        let all = AgentLauncher.builtInPresets
        var installed: [AgentLauncher] = []

        for agent in all {
            if await isInstalled(agent) {
                installed.append(agent)
            }
        }
        return installed
    }

    /// Checks whether a single agent's command is available on PATH.
    func isInstalled(_ agent: AgentLauncher) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [agent.command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}

// MARK: - AgentLauncherRecord Helpers

extension AgentLauncherRecord {
    /// Decodes the JSON-encoded args array, returning empty array on failure.
    var decodedArgs: [String] {
        guard let json = argsJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
