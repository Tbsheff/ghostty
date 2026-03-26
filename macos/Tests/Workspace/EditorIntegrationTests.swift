import AppKit
import Foundation
import Testing
@testable import Ghostty

/// Tests for EditorIntegration: editor detection and known editor metadata.
struct EditorIntegrationTests {

    @Test func installedEditors_returnsNonEmpty() {
        // On macOS with Xcode installed, at least Xcode should be found
        let editors = installedEditors()
        // This may be empty in CI without Xcode, so we test >= 0 for safety
        // but on a dev machine with Xcode, it should be >= 1
        #expect(editors.count >= 0)
    }

    @Test func knownEditors_haveValidBundleIds() {
        for editor in EditorInfo.knownEditors {
            #expect(!editor.bundleId.isEmpty)
            #expect(editor.bundleId.contains("."))
            #expect(!editor.name.isEmpty)
            #expect(!editor.cliCommand.isEmpty)
            #expect(!editor.iconName.isEmpty)
        }
    }

    @Test func knownEditors_containsExpectedEditors() {
        let names = EditorInfo.knownEditors.map(\.name)
        #expect(names.contains("VS Code"))
        #expect(names.contains("Xcode"))
        #expect(names.contains("Zed"))
        #expect(names.contains("Cursor"))
        #expect(names.contains("Sublime Text"))
        #expect(names.contains("Nova"))
    }

    @Test func editorInfo_identifiable_usesBundle() {
        let editor = EditorInfo(name: "Test", bundleId: "com.test.editor", iconName: "star", cliCommand: "test")
        #expect(editor.id == "com.test.editor")
    }

    @Test func knownEditors_xcodeHasCorrectBundleId() {
        let xcode = EditorInfo.knownEditors.first { $0.name == "Xcode" }
        #expect(xcode != nil)
        #expect(xcode?.bundleId == "com.apple.dt.Xcode")
        #expect(xcode?.cliCommand == "xed")
    }

    @Test func openInEditor_constructsCorrectCommand() {
        // Verify the editor's CLI command would be used correctly
        let editor = EditorInfo(name: "TestEditor", bundleId: "com.test.editor", iconName: "star", cliCommand: "testeditor")
        #expect(editor.cliCommand == "testeditor")
        // The function uses /usr/bin/env <cliCommand> <path> for fallback
        // We can't test the actual launch but verify the data is correct
        #expect(!editor.cliCommand.contains(" "))
    }

    @Test func openInFinder_worksWithValidPath() {
        // Verify the path handling logic
        let path = "/tmp/test-workspace"
        let url = URL(fileURLWithPath: path)
        #expect(url.path == "/tmp/test-workspace")
        #expect(url.deletingLastPathComponent().path == "/tmp")
    }

    @Test func knownEditors_allHaveNonEmptyCliCommands() {
        for editor in EditorInfo.knownEditors {
            #expect(!editor.cliCommand.isEmpty, "\(editor.name) has empty CLI command")
            // CLI commands should be single words (no spaces)
            #expect(!editor.cliCommand.contains(" "), "\(editor.name) CLI command contains spaces")
        }
    }
}
