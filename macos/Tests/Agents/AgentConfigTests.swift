import Foundation
import Testing
@testable import Ghostty

/// Tests for AgentConfig built-in presets and agent metadata.
struct AgentConfigTests {

    @Test func testBuiltInPresets_containsExpectedAgents() {
        let presets = AgentLauncher.builtInPresets
        let names = presets.map(\.name)

        #expect(names.contains("Claude Code"))
        #expect(names.contains("Codex"))
        #expect(names.contains("Gemini"))
        #expect(names.contains("Aider"))
    }

    @Test func testBuiltInPresets_allHaveValidCommands() {
        for agent in AgentLauncher.builtInPresets {
            #expect(!agent.command.isEmpty, "Agent '\(agent.name)' has empty command")
            #expect(!agent.name.isEmpty, "Agent has empty name")
            #expect(!agent.icon.isEmpty, "Agent '\(agent.name)' has empty icon")
            #expect(!agent.color.isEmpty, "Agent '\(agent.name)' has empty color")
            #expect(agent.color.hasPrefix("#"), "Agent '\(agent.name)' color should be hex")
        }
    }

    @Test func testBuiltInPresets_haveUniqueIds() {
        let ids = AgentLauncher.builtInPresets.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Built-in presets should have unique IDs")
    }

    @Test func testBuiltInPresets_haveUniqueCommands() {
        let commands = AgentLauncher.builtInPresets.map(\.command)
        let uniqueCommands = Set(commands)
        #expect(commands.count == uniqueCommands.count, "Built-in presets should have unique commands")
    }

    @Test func testAgentLauncher_identifiable() {
        let agent = AgentLauncher(name: "Test", command: "test", icon: "star", color: "#000000")
        #expect(!agent.id.isEmpty)
    }

    @Test func testAgentLauncherRecord_decodedArgs_emptyJSON() {
        let record = AgentLauncherRecord(name: "Test", command: "test", argsJSON: nil)
        #expect(record.decodedArgs.isEmpty)
    }

    @Test func testAgentLauncherRecord_decodedArgs_validJSON() {
        let record = AgentLauncherRecord(name: "Test", command: "test", argsJSON: "[\"--flag\",\"value\"]")
        #expect(record.decodedArgs == ["--flag", "value"])
    }

    @Test func testAgentLauncherRecord_decodedArgs_invalidJSON() {
        let record = AgentLauncherRecord(name: "Test", command: "test", argsJSON: "not json")
        #expect(record.decodedArgs.isEmpty)
    }

    @Test func testClaudePreset_hasCorrectEnvVar() {
        let claude = AgentLauncher.builtInPresets.first { $0.name == "Claude Code" }
        #expect(claude != nil)
        #expect(claude?.requiredEnvVars.contains("ANTHROPIC_API_KEY") == true)
        #expect(claude?.command == "claude")
    }
}
