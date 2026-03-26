import Foundation

// MARK: - HibernationManager

/// Manages worktree hibernation to bound memory usage.
///
/// When the number of live (non-hibernated) worktrees exceeds `maxLiveWorktrees`,
/// or a worktree has been idle longer than `hibernateAfter`, the manager serializes
/// its `SplitTreeLayout` to SQLite and releases the live terminal surfaces.
///
/// Wake restores the layout by inflating fresh surfaces in the saved working directories.
///
/// Integrates with `SessionAutoSaver` for serialization and `WorkspaceStore` for
/// persistence of hibernation state.
@MainActor
final class HibernationManager: ObservableObject {
    var maxLiveWorktrees: Int
    var hibernateAfter: TimeInterval

    @Published private(set) var hibernatedIds: Set<String> = []
    private var lastActiveAt: [String: Date] = [:]

    private var checkTimer: Timer?
    private let checkInterval: TimeInterval = 60

    private let autoSaver: SessionAutoSaver
    private let store: WorkspaceStore

    /// Callbacks invoked by the manager. The host (e.g., WorkspaceState) implements these
    /// to perform the actual surface teardown/creation since HibernationManager does not
    /// own any Ghostty types directly.
    struct Callbacks {
        /// Called to capture the current SplitTreeLayout for a worktree before hibernation.
        var captureLayout: (_ worktreeId: String) -> SplitTreeLayout?

        /// Called to release all live terminal surfaces for a worktree.
        var releaseSurfaces: (_ worktreeId: String) -> Void

        /// Called to inflate a SplitTreeLayout into live surfaces when waking.
        var inflateSurfaces: (_ worktreeId: String, _ layout: SplitTreeLayout) -> Void
    }

    var callbacks: Callbacks?

    init(
        maxLiveWorktrees: Int = 5,
        hibernateAfter: TimeInterval = 600,
        autoSaver: SessionAutoSaver,
        store: WorkspaceStore = WorkspaceStore()
    ) {
        self.maxLiveWorktrees = maxLiveWorktrees
        self.hibernateAfter = hibernateAfter
        self.autoSaver = autoSaver
        self.store = store
    }

    // MARK: - Lifecycle

    func start() {
        stop()
        checkTimer = Timer.scheduledTimer(
            withTimeInterval: checkInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.checkIdleWorktrees() }
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    deinit {
        // Timer invalidation is safe from any thread as of macOS 10.12+,
        // and stop() is called from the owning controller's cleanup path.
        // This is a safety net in case stop() wasn't called.
        checkTimer?.invalidate()
    }

    // MARK: - Activity Tracking

    /// Called when a worktree becomes active (selected, interacted with).
    func touchWorktree(_ worktreeId: String) {
        lastActiveAt[worktreeId] = Date()
    }

    /// Called when a worktree is removed entirely.
    func removeWorktree(_ worktreeId: String) {
        lastActiveAt.removeValue(forKey: worktreeId)
        hibernatedIds.remove(worktreeId)
    }

    // MARK: - Queries

    func isHibernated(_ worktreeId: String) -> Bool {
        hibernatedIds.contains(worktreeId)
    }

    func shouldHibernate(_ worktreeId: String) -> Bool {
        guard !isHibernated(worktreeId) else { return false }
        guard let lastActive = lastActiveAt[worktreeId] else { return false }
        return Date().timeIntervalSince(lastActive) >= hibernateAfter
    }

    // MARK: - Hibernate

    /// Serializes the worktree's layout to SQLite and releases live surfaces.
    func hibernate(worktreeId: String) {
        guard !isHibernated(worktreeId) else { return }

        // Capture and persist layout
        if let layout = callbacks?.captureLayout(worktreeId) {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(layout),
               let json = String(data: data, encoding: .utf8) {
                try? store.updateSession(workspaceId: worktreeId, splitTreeJSON: json)
            }
        }

        // Release surfaces
        callbacks?.releaseSurfaces(worktreeId)
        hibernatedIds.insert(worktreeId)
    }

    // MARK: - Wake

    /// Restores a hibernated worktree by inflating its saved layout.
    func wake(worktreeId: String) {
        guard isHibernated(worktreeId) else { return }

        // Load saved layout from DB
        guard let session = try? store.activeSession(forWorkspaceId: worktreeId),
              let json = session.splitTreeJSON,
              let data = json.data(using: .utf8),
              let layout = try? JSONDecoder().decode(SplitTreeLayout.self, from: data) else {
            // No saved layout — just mark as awake, caller will create fresh terminal
            hibernatedIds.remove(worktreeId)
            touchWorktree(worktreeId)
            return
        }

        callbacks?.inflateSurfaces(worktreeId, layout)
        hibernatedIds.remove(worktreeId)
        touchWorktree(worktreeId)
    }

    // MARK: - LRU Eviction

    /// Called when opening a new worktree. If we're at the live limit,
    /// hibernates the least-recently-used worktree.
    func evictIfNeeded(excluding activeWorktreeId: String) {
        let liveIds = Set(lastActiveAt.keys).subtracting(hibernatedIds)
        guard liveIds.count >= maxLiveWorktrees else { return }

        // Find LRU among live worktrees (excluding the active one)
        let candidates = liveIds.subtracting([activeWorktreeId])
        guard let lruId = candidates.min(by: {
            (lastActiveAt[$0] ?? .distantPast) < (lastActiveAt[$1] ?? .distantPast)
        }) else { return }

        hibernate(worktreeId: lruId)
    }

    // MARK: - Periodic Check

    private func checkIdleWorktrees() {
        let liveIds = Set(lastActiveAt.keys).subtracting(hibernatedIds)
        for worktreeId in liveIds {
            if shouldHibernate(worktreeId) {
                hibernate(worktreeId: worktreeId)
            }
        }
    }
}
