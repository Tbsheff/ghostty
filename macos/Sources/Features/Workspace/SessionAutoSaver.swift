import Foundation

// MARK: - PendingSave

/// Captures the data needed to persist a session update.
private struct PendingSave {
    let workspaceId: String
    let layout: SplitTreeLayout
    let focusedSurfaceId: String?
}

// MARK: - SessionAutoSaver

/// Debounced session auto-saver that batches split tree layout changes
/// before flushing them to the database.
///
/// All mutations must happen on MainActor since this interacts with
/// UI state (surfaceTree changes) and uses a main-thread Timer.
///
/// Usage:
///   - Call `scheduleSave(...)` on every surfaceTree change
///   - Call `saveNow()` on workspace switch, app quit, or window resign key
///   - The 2-second debounce prevents write storms during rapid split/resize
@MainActor
final class SessionAutoSaver {

    private let store: WorkspaceStore
    private let debounceInterval: TimeInterval

    private var debounceTimer: Timer?
    private var pendingSaves: [String: PendingSave] = [:]

    init(store: WorkspaceStore, debounceInterval: TimeInterval = 2.0) {
        self.store = store
        self.debounceInterval = debounceInterval
    }

    // MARK: - Public API

    /// Schedules a session save for the given workspace, resetting the debounce timer.
    ///
    /// Multiple calls within the debounce window are coalesced — only the latest
    /// layout for each workspace is persisted when the timer fires.
    func scheduleSave(
        workspaceId: String,
        layout: SplitTreeLayout,
        focusedSurfaceId: String?
    ) {
        pendingSaves[workspaceId] = PendingSave(
            workspaceId: workspaceId,
            layout: layout,
            focusedSurfaceId: focusedSurfaceId
        )

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.flushPendingSaves()
            }
        }
    }

    /// Immediately flushes all pending saves, bypassing the debounce timer.
    ///
    /// Call this on:
    /// - Workspace switch (before loading new workspace)
    /// - App quit / `applicationWillTerminate`
    /// - Window resign key
    func saveNow() async {
        debounceTimer?.invalidate()
        debounceTimer = nil
        await flushPendingSaves()
    }

    // MARK: - Private

    /// Encodes each pending layout to JSON and writes to the store.
    private func flushPendingSaves() async {
        let saves = pendingSaves
        pendingSaves.removeAll()

        guard !saves.isEmpty else { return }

        let encoder = JSONEncoder()

        for (_, save) in saves {
            do {
                let jsonData = try encoder.encode(save.layout)
                let jsonString = String(data: jsonData, encoding: .utf8)

                // WorkspaceStore.updateSession is synchronous (GRDB write)
                try store.updateSession(
                    workspaceId: save.workspaceId,
                    splitTreeJSON: jsonString,
                    focusedSurfaceID: save.focusedSurfaceId
                )
            } catch {
                // Log but don't propagate — auto-save is best-effort.
                // The next save cycle will retry with the latest state.
                #if DEBUG
                print("[SessionAutoSaver] Failed to save session for workspace \(save.workspaceId): \(error)")
                #endif
            }
        }
    }
}
