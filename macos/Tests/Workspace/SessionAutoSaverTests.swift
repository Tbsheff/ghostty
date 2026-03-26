import Foundation
import GRDB
import Testing
@testable import Ghostty

/// Tests for SessionAutoSaver debounced saving behavior.
///
/// Uses an in-memory GRDB database to verify that scheduled saves are
/// debounced and that saveNow() flushes immediately.
struct SessionAutoSaverTests {

    // MARK: - Helpers

    /// Creates an in-memory store with schema applied.
    private func makeStore() throws -> WorkspaceStore {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let dbQueue = try DatabaseQueue(configuration: config)

        var migrator = DatabaseMigrator()
        Migration001_InitialSchema.register(in: &migrator)
        try migrator.migrate(dbQueue)

        return WorkspaceStore(dbPool: dbQueue)
    }

    /// Creates a project + workspace + active session in the store.
    private func seedWorkspace(store: WorkspaceStore) throws -> WorkspaceRecord {
        let project = try store.createProject(name: "Repo", repoPath: "/tmp/auto-save-test")
        let workspace = try store.createWorkspace(
            projectId: project.id,
            name: "main",
            branch: "main",
            worktreePath: "/tmp/auto-save-test/main"
        )
        _ = try store.saveSession(workspaceId: workspace.id, splitTreeJSON: "initial")
        return workspace
    }

    private func makeLayout(uuid: String = "test") -> SplitTreeLayout {
        SplitTreeLayout(
            root: .leaf(SurfaceLayout(uuid: uuid, pwd: "/tmp", title: "T", isUserSetTitle: false)),
            zoomedPath: nil
        )
    }

    // MARK: - Tests

    @Test @MainActor func scheduleSave_debounces_doesNotSaveImmediately() async throws {
        let store = try makeStore()
        let workspace = try seedWorkspace(store: store)

        // Use a long debounce so the timer doesn't fire during this test
        let saver = SessionAutoSaver(store: store, debounceInterval: 10.0)

        saver.scheduleSave(
            workspaceId: workspace.id,
            layout: makeLayout(uuid: "scheduled"),
            focusedSurfaceId: nil
        )

        // Check immediately — the session should still have the original JSON
        let session = try store.activeSession(forWorkspaceId: workspace.id)
        #expect(session?.splitTreeJSON == "initial")
    }

    @Test @MainActor func scheduleSave_afterDebounce_saves() async throws {
        let store = try makeStore()
        let workspace = try seedWorkspace(store: store)

        // Very short debounce for test
        let saver = SessionAutoSaver(store: store, debounceInterval: 0.1)

        saver.scheduleSave(
            workspaceId: workspace.id,
            layout: makeLayout(uuid: "debounced"),
            focusedSurfaceId: nil
        )

        // Wait for debounce + flush
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        let session = try store.activeSession(forWorkspaceId: workspace.id)
        #expect(session?.splitTreeJSON != "initial")
        #expect(session?.splitTreeJSON?.contains("debounced") == true)
    }

    @Test @MainActor func saveNow_savesImmediately() async throws {
        let store = try makeStore()
        let workspace = try seedWorkspace(store: store)

        let saver = SessionAutoSaver(store: store, debounceInterval: 60.0) // Long debounce

        saver.scheduleSave(
            workspaceId: workspace.id,
            layout: makeLayout(uuid: "immediate"),
            focusedSurfaceId: "focus-id"
        )

        // Force immediate save
        await saver.saveNow()

        let session = try store.activeSession(forWorkspaceId: workspace.id)
        #expect(session?.splitTreeJSON?.contains("immediate") == true)
        #expect(session?.focusedSurfaceID == "focus-id")
    }

    @Test @MainActor func multipleSaves_coalesced_onlyLastSaved() async throws {
        let store = try makeStore()
        let workspace = try seedWorkspace(store: store)

        let saver = SessionAutoSaver(store: store, debounceInterval: 60.0)

        // Schedule multiple saves rapidly
        saver.scheduleSave(workspaceId: workspace.id, layout: makeLayout(uuid: "v1"), focusedSurfaceId: nil)
        saver.scheduleSave(workspaceId: workspace.id, layout: makeLayout(uuid: "v2"), focusedSurfaceId: nil)
        saver.scheduleSave(workspaceId: workspace.id, layout: makeLayout(uuid: "v3-final"), focusedSurfaceId: nil)

        // Force flush
        await saver.saveNow()

        let session = try store.activeSession(forWorkspaceId: workspace.id)
        // Only the last scheduled layout should be persisted
        #expect(session?.splitTreeJSON?.contains("v3-final") == true)
        #expect(session?.splitTreeJSON?.contains("v1") != true)
    }
}
