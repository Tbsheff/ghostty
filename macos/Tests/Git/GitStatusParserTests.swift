import Foundation
import Testing
@testable import Ghostty

/// Tests for GitStatusManager's parsePorcelainV2 parser using synthetic input.
///
/// These tests verify parsing logic without hitting the git CLI,
/// complementing the integration tests in GitStatusManagerTests.
struct GitStatusParserTests {
    private let manager = GitStatusManager()

    @Test func testParsePorcelainV2_ordinaryModified() async {
        let output = "1 .M N... 100644 100644 100644 abc123 def456 src/main.swift"
        let files = await manager.parsePorcelainV2(output)

        #expect(files.count == 1)
        #expect(files[0].path == "src/main.swift")
        #expect(files[0].status == .modified)
        #expect(files[0].isStaged == false)
    }

    @Test func testParsePorcelainV2_stagedModified() async {
        let output = "1 M. N... 100644 100644 100644 abc123 def456 src/main.swift"
        let files = await manager.parsePorcelainV2(output)

        #expect(files.count == 1)
        #expect(files[0].path == "src/main.swift")
        #expect(files[0].status == .modified)
        #expect(files[0].isStaged == true)
    }

    @Test func testParsePorcelainV2_renamed() async {
        // Format: 2 R. N... 100644 100644 100644 abc123 def456 R100 new.swift\told.swift
        let output = "2 R. N... 100644 100644 100644 abc123 def456 R100 new.swift\told.swift"
        let files = await manager.parsePorcelainV2(output)

        #expect(files.count == 1)
        #expect(files[0].path == "new.swift")
        #expect(files[0].status == .renamed)
        #expect(files[0].isStaged == true)
        #expect(files[0].originalPath == "old.swift")
    }

    @Test func testParsePorcelainV2_untracked() async {
        let output = "? untracked-file.txt"
        let files = await manager.parsePorcelainV2(output)

        #expect(files.count == 1)
        #expect(files[0].path == "untracked-file.txt")
        #expect(files[0].status == .untracked)
        #expect(files[0].isStaged == false)
    }

    @Test func testParsePorcelainV2_mixedStatus() async {
        let output = """
        1 M. N... 100644 100644 100644 abc123 def456 staged.swift
        1 .M N... 100644 100644 100644 abc123 def456 unstaged.swift
        ? new-file.txt
        1 A. N... 100644 100644 100644 abc123 def456 added.swift
        """
        let files = await manager.parsePorcelainV2(output)

        #expect(files.count == 4)

        let staged = files.filter { $0.isStaged }
        let unstaged = files.filter { !$0.isStaged }

        #expect(staged.count == 2) // M staged + A staged
        #expect(unstaged.count == 2) // .M unstaged + ? untracked
    }

    @Test func testParsePorcelainV2_deleted() async {
        let output = "1 D. N... 100644 000000 000000 abc123 000000 deleted.swift"
        let files = await manager.parsePorcelainV2(output)

        #expect(files.count == 1)
        #expect(files[0].status == .deleted)
        #expect(files[0].isStaged == true)
    }

    @Test func testParsePorcelainV2_bothStagedAndUnstaged() async {
        // MM = modified in both index and worktree
        let output = "1 MM N... 100644 100644 100644 abc123 def456 both.swift"
        let files = await manager.parsePorcelainV2(output)

        #expect(files.count == 2)
        let staged = files.first { $0.isStaged }
        let unstaged = files.first { !$0.isStaged }
        #expect(staged?.status == .modified)
        #expect(unstaged?.status == .modified)
    }

    @Test func testParsePorcelainV2_emptyOutput() async {
        let files = await manager.parsePorcelainV2("")
        #expect(files.isEmpty)
    }

    @Test func testGitFileStatus_fileName() {
        let file = GitFileStatus(path: "src/features/auth.swift", originalPath: nil, status: .modified, isStaged: false)
        #expect(file.fileName == "auth.swift")
    }

    @Test func testGitFileStatus_directory() {
        let file = GitFileStatus(path: "src/features/auth.swift", originalPath: nil, status: .modified, isStaged: false)
        #expect(file.directory == "src/features")
    }

    @Test func testGitFileStatus_directory_rootFile() {
        let file = GitFileStatus(path: "README.md", originalPath: nil, status: .modified, isStaged: false)
        #expect(file.directory == "")
    }
}
