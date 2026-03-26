import Combine
import Foundation

// MARK: - WorktreeProcessState

/// Aggregated process state for a single worktree, used for sidebar badges.
struct WorktreeProcessState: Equatable {
    let worktreeId: String
    var anyRunning: Bool = false
    var anyBell: Bool = false
    var activeProcessNames: Set<String> = []
}

// MARK: - ProcessTracker

/// Tracks per-worktree terminal process activity by polling surface properties.
///
/// Publishes `WorktreeProcessState` changes so the sidebar can render badges
/// (running indicator, bell indicator, process names).
///
/// Polling rates:
///   - 1 second for the active worktree (responsive feedback)
///   - 5 seconds for background worktrees (low overhead)
@MainActor
final class ProcessTracker: ObservableObject {
    @Published private(set) var states: [String: WorktreeProcessState] = [:]

    private var activeTimer: Timer?
    private var backgroundTimer: Timer?
    private var activeWorktreeId: String?

    /// Surfaces grouped by worktree ID. Updated externally when tabs change.
    private var surfacesByWorktree: [String: [SurfaceHandle]] = [:]

    private let activeInterval: TimeInterval
    private let backgroundInterval: TimeInterval

    /// Lightweight handle to a Ghostty surface for polling without retaining the view.
    struct SurfaceHandle {
        let worktreeId: String
        let getTitle: () -> String?
        let getPwd: () -> String?
        let hasBell: () -> Bool
    }

    init(activeInterval: TimeInterval = 1.0, backgroundInterval: TimeInterval = 5.0) {
        self.activeInterval = activeInterval
        self.backgroundInterval = backgroundInterval
    }

    // MARK: - Lifecycle

    func start() {
        stop()

        activeTimer = Timer.scheduledTimer(
            withTimeInterval: activeInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.pollActive() }
        }

        backgroundTimer = Timer.scheduledTimer(
            withTimeInterval: backgroundInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.pollBackground() }
        }
    }

    func stop() {
        activeTimer?.invalidate()
        activeTimer = nil
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }

    deinit {
        // Timer invalidation is safe from any thread as of macOS 10.12+,
        // and stop() is called from the owning controller's cleanup path.
        // This is a safety net in case stop() wasn't called.
        activeTimer?.invalidate()
        backgroundTimer?.invalidate()
    }

    // MARK: - Configuration

    func setActiveWorktree(_ worktreeId: String?) {
        activeWorktreeId = worktreeId
    }

    /// Register surfaces for a worktree. Call when tabs/splits change.
    func updateSurfaces(worktreeId: String, handles: [SurfaceHandle]) {
        surfacesByWorktree[worktreeId] = handles
        if states[worktreeId] == nil {
            states[worktreeId] = WorktreeProcessState(worktreeId: worktreeId)
        }
    }

    /// Remove tracking for a worktree (e.g., when hibernated or deleted).
    func removeWorktree(_ worktreeId: String) {
        surfacesByWorktree.removeValue(forKey: worktreeId)
        states.removeValue(forKey: worktreeId)
    }

    // MARK: - Polling

    private func pollActive() {
        guard let id = activeWorktreeId else { return }
        pollWorktree(id)
    }

    private func pollBackground() {
        for worktreeId in surfacesByWorktree.keys where worktreeId != activeWorktreeId {
            pollWorktree(worktreeId)
        }
    }

    private func pollWorktree(_ worktreeId: String) {
        guard let handles = surfacesByWorktree[worktreeId] else { return }

        var state = WorktreeProcessState(worktreeId: worktreeId)

        for handle in handles {
            if let title = handle.getTitle(), !title.isEmpty {
                // A non-shell title typically indicates a running process.
                // Common shell names are excluded to detect "running" state.
                let shellNames: Set<String> = ["zsh", "bash", "fish", "sh", "nu", "pwsh"]
                let baseName = title.components(separatedBy: " ").first ?? title
                if !shellNames.contains(baseName.lowercased()) {
                    state.anyRunning = true
                    state.activeProcessNames.insert(baseName)
                }
            }

            if handle.hasBell() {
                state.anyBell = true
            }
        }

        states[worktreeId] = state
    }

    /// Clears the bell indicator for a worktree (e.g., when the user selects it).
    func clearBell(worktreeId: String) {
        states[worktreeId]?.anyBell = false
    }
}
