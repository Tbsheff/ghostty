import Foundation
import GRDB
import Testing
@testable import Ghostty

/// Tests for HibernationManager idle/eviction/wake logic.
///
/// Uses an in-memory DB and mock callbacks to verify behavior
/// without requiring live Ghostty surfaces.
struct HibernationManagerTests {

    // MARK: - Helpers

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

    private func makeLayout(uuid: String = "test") -> SplitTreeLayout {
        SplitTreeLayout(
            root: .leaf(SurfaceLayout(uuid: uuid, pwd: "/tmp", title: "T", isUserSetTitle: false)),
            zoomedPath: nil
        )
    }

    @MainActor
    private func makeManager(
        store: WorkspaceStore,
        maxLive: Int = 3,
        hibernateAfter: TimeInterval = 600
    ) -> HibernationManager {
        let saver = SessionAutoSaver(store: store, debounceInterval: 60)
        return HibernationManager(
            maxLiveWorktrees: maxLive,
            hibernateAfter: hibernateAfter,
            autoSaver: saver,
            store: store
        )
    }

    // MARK: - Tests

    @Test @MainActor func testHibernate_serializesAndMarksHibernated() throws {
        let store = try makeStore()
        let manager = makeManager(store: store)

        // Seed a workspace so updateSession has something to update
        let project = try store.createProject(name: "Repo", repoPath: "/tmp/hib-test")
        let workspace = try store.createWorkspace(
            projectId: project.id, name: "wt1", branch: "main",
            worktreePath: "/tmp/hib-test/main"
        )
        _ = try store.saveSession(workspaceId: workspace.id, splitTreeJSON: "original")

        // Set up callbacks
        var capturedWorktreeId: String?
        var releasedWorktreeId: String?
        manager.callbacks = HibernationManager.Callbacks(
            captureLayout: { wtId in
                capturedWorktreeId = wtId
                return self.makeLayout(uuid: "hibernated-layout")
            },
            releaseSurfaces: { wtId in
                releasedWorktreeId = wtId
            },
            inflateSurfaces: { _, _ in }
        )

        manager.touchWorktree(workspace.id)
        manager.hibernate(worktreeId: workspace.id)

        #expect(manager.isHibernated(workspace.id))
        #expect(capturedWorktreeId == workspace.id)
        #expect(releasedWorktreeId == workspace.id)
    }

    @Test @MainActor func testWake_inflatesAndClearsHibernated() throws {
        let store = try makeStore()
        let manager = makeManager(store: store)

        let project = try store.createProject(name: "Repo", repoPath: "/tmp/wake-test")
        let workspace = try store.createWorkspace(
            projectId: project.id, name: "wt1", branch: "main",
            worktreePath: "/tmp/wake-test/main"
        )

        // Save a session with layout JSON
        let layout = makeLayout(uuid: "wake-layout")
        let data = try JSONEncoder().encode(layout)
        let json = String(data: data, encoding: .utf8)!
        _ = try store.saveSession(workspaceId: workspace.id, splitTreeJSON: json)

        var inflatedLayout: SplitTreeLayout?
        manager.callbacks = HibernationManager.Callbacks(
            captureLayout: { _ in self.makeLayout() },
            releaseSurfaces: { _ in },
            inflateSurfaces: { _, layout in inflatedLayout = layout }
        )

        // Hibernate first, then wake
        manager.touchWorktree(workspace.id)
        manager.hibernate(worktreeId: workspace.id)
        #expect(manager.isHibernated(workspace.id))

        manager.wake(worktreeId: workspace.id)

        #expect(!manager.isHibernated(workspace.id))
        #expect(inflatedLayout != nil)
    }

    @Test @MainActor func testLRUEviction_hibernatesLeastRecentlyUsed() async throws {
        let store = try makeStore()
        let manager = makeManager(store: store, maxLive: 2)

        var hibernatedIds: [String] = []
        manager.callbacks = HibernationManager.Callbacks(
            captureLayout: { _ in nil },
            releaseSurfaces: { wtId in hibernatedIds.append(wtId) },
            inflateSurfaces: { _, _ in }
        )

        // Touch three worktrees with small delays so timestamps differ
        manager.touchWorktree("wt-old")
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        manager.touchWorktree("wt-mid")
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        manager.touchWorktree("wt-new")

        // Evict, excluding the newest
        manager.evictIfNeeded(excluding: "wt-new")

        // Should have hibernated the oldest (wt-old)
        #expect(manager.isHibernated("wt-old"))
        #expect(!manager.isHibernated("wt-mid"))
        #expect(!manager.isHibernated("wt-new"))
    }

    @Test @MainActor func testIdleTimeout_hibernatesAfterConfiguredTime() throws {
        let store = try makeStore()
        // Use a very short idle timeout
        let manager = makeManager(store: store, hibernateAfter: 0.0)

        manager.touchWorktree("wt-idle")

        // With hibernateAfter=0, it should immediately qualify
        #expect(manager.shouldHibernate("wt-idle"))
    }

    @Test @MainActor func testActiveWorktree_neverHibernated() throws {
        let store = try makeStore()
        let manager = makeManager(store: store, hibernateAfter: 0.0)

        // Already hibernated worktrees should return false for shouldHibernate
        manager.touchWorktree("wt-active")
        manager.hibernate(worktreeId: "wt-active")

        // Once hibernated, shouldHibernate returns false (guard clause)
        #expect(!manager.shouldHibernate("wt-active"))
    }
}
