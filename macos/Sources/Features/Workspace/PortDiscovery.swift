import AppKit
import Foundation

// MARK: - PortInfo

/// A discovered listening TCP port associated with a worktree's process tree.
struct PortInfo: Identifiable, Equatable, Sendable {
    let port: UInt16
    let processName: String
    let pid: Int32
    let worktreeId: String

    var id: String { "\(worktreeId)-\(port)" }
}

// MARK: - PortDiscovery

/// Discovers TCP ports listening on localhost by polling `lsof` and matching
/// PIDs to worktrees via the process parent chain.
///
/// Polling rates:
///   - 3 seconds for the active worktree
///   - 15 seconds for background worktrees
actor PortDiscovery {
    private var ports: [String: [PortInfo]] = [:]  // worktreeId -> ports
    private var shellPids: [String: Set<Int32>] = [:]  // worktreeId -> known shell PIDs
    private var activeWorktreeId: String?

    private var activeTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?

    private let activeInterval: TimeInterval
    private let backgroundInterval: TimeInterval

    init(activeInterval: TimeInterval = 3.0, backgroundInterval: TimeInterval = 15.0) {
        self.activeInterval = activeInterval
        self.backgroundInterval = backgroundInterval
    }

    // MARK: - Lifecycle

    func start() {
        stop()

        activeTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollPorts(activeOnly: true)
                try? await Task.sleep(nanoseconds: UInt64(self.activeInterval * 1_000_000_000))
            }
        }

        backgroundTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollPorts(activeOnly: false)
                try? await Task.sleep(nanoseconds: UInt64(self.backgroundInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        activeTask?.cancel()
        activeTask = nil
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    // MARK: - Configuration

    func setActiveWorktree(_ worktreeId: String?) {
        activeWorktreeId = worktreeId
    }

    /// Register shell PIDs for a worktree so port discovery can match via parent chain.
    func registerShellPids(_ pids: Set<Int32>, forWorktreeId worktreeId: String) {
        shellPids[worktreeId] = pids
    }

    func removeWorktree(_ worktreeId: String) {
        ports.removeValue(forKey: worktreeId)
        shellPids.removeValue(forKey: worktreeId)
    }

    // MARK: - Queries

    func discoveredPorts(forWorktreeId worktreeId: String) -> [PortInfo] {
        ports[worktreeId] ?? []
    }

    func allDiscoveredPorts() -> [PortInfo] {
        ports.values.flatMap { $0 }
    }

    // MARK: - Actions

    @MainActor
    func openInBrowser(port: UInt16) {
        guard let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Polling

    private func pollPorts(activeOnly: Bool) async {
        let worktreeIds: Set<String>
        if activeOnly {
            guard let id = activeWorktreeId else { return }
            worktreeIds = [id]
        } else {
            worktreeIds = Set(shellPids.keys).subtracting([activeWorktreeId].compactMap { $0 })
        }

        guard !worktreeIds.isEmpty else { return }

        // Run lsof to find all listening TCP ports
        guard let lsofOutput = await runLsof() else { return }
        let entries = parseLsofOutput(lsofOutput)

        // Build parent PID lookup
        let parentChains = await buildParentChains(for: Set(entries.map(\.pid)))

        // Match each listening port to a worktree
        var newPorts: [String: [PortInfo]] = [:]

        for entry in entries {
            for worktreeId in worktreeIds {
                guard let pids = shellPids[worktreeId] else { continue }
                let chain = parentChains[entry.pid] ?? []
                if pids.contains(entry.pid) || chain.contains(where: { pids.contains($0) }) {
                    var list = newPorts[worktreeId] ?? []
                    list.append(PortInfo(
                        port: entry.port,
                        processName: entry.processName,
                        pid: entry.pid,
                        worktreeId: worktreeId
                    ))
                    newPorts[worktreeId] = list
                }
            }
        }

        // Update ports for polled worktrees
        for worktreeId in worktreeIds {
            ports[worktreeId] = newPorts[worktreeId] ?? []
        }
    }

    // MARK: - lsof Parsing

    private struct LsofEntry {
        let processName: String
        let pid: Int32
        let port: UInt16
    }

    private func runLsof() async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Parses lsof output lines like:
    /// `node    12345 user   20u  IPv4 0x...  0t0  TCP *:3000 (LISTEN)`
    private func parseLsofOutput(_ output: String) -> [LsofEntry] {
        output.components(separatedBy: "\n").compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 9 else { return nil }

            let processName = String(fields[0])
            guard let pid = Int32(fields[1]) else { return nil }

            // Find the TCP field containing the port, e.g., "*:3000" or "127.0.0.1:8080"
            let tcpField = String(fields[8])
            guard let colonIndex = tcpField.lastIndex(of: ":") else { return nil }
            let portString = tcpField[tcpField.index(after: colonIndex)...]
            guard let port = UInt16(portString) else { return nil }

            return LsofEntry(processName: processName, pid: pid, port: port)
        }
    }

    // MARK: - Parent Chain

    /// Builds a mapping of PID -> [ancestor PIDs] using `ps`.
    private func buildParentChains(for pids: Set<Int32>) async -> [Int32: [Int32]] {
        guard !pids.isEmpty else { return [:] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,ppid"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        // Parse pid -> ppid mapping
        var ppidMap: [Int32: Int32] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { continue }
            ppidMap[pid] = ppid
        }

        // Walk parent chains for requested PIDs
        var chains: [Int32: [Int32]] = [:]
        for pid in pids {
            var chain: [Int32] = []
            var current = ppidMap[pid]
            while let parent = current, parent > 1 {
                chain.append(parent)
                current = ppidMap[parent]
                if chain.count > 20 { break }  // Guard against cycles
            }
            chains[pid] = chain
        }

        return chains
    }
}
