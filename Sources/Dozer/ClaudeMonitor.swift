import Foundation

/// What Dozer currently knows about Claude.
struct ClaudeActivity: Equatable {
    /// Claude Code sessions that are mid-task (reported by the hooks).
    var activeSessions: Int = 0
    /// `claude` CLI processes currently burning CPU (heuristic fallback).
    var busyProcesses: Int = 0
    /// Any `claude` CLI process running at all, busy or not.
    var runningProcesses: Int = 0
    /// Terminals with a command or busy CLI agent running (see `TerminalMonitor`).
    var busyTerminals: [TerminalMonitor.BusyTerminal] = []
    /// Watched apps that are working, or open when set to "While open" (see `AppMonitor`).
    var busyApps: [AppMonitor.BusyApp] = []
    /// A download or upload in progress (see `NetworkMonitor`).
    var transfer: NetworkMonitor.Transfer?

    var isClaudeWorking: Bool { activeSessions > 0 || busyProcesses > 0 }
    var isWorking: Bool { isClaudeWorking || !busyTerminals.isEmpty || !busyApps.isEmpty || transfer != nil }
}

/// Detects whether Claude is working, using two signals:
///
/// 1. **Hooks (precise).** Dozer installs Claude Code hooks that drop a
///    marker file per session when a prompt is submitted / a tool runs, and
///    delete it when Claude stops. A marker present = a task in flight.
/// 2. **Process heuristic (fallback).** A `claude` CLI process that keeps
///    using more than a little CPU counts as working, which covers sessions
///    that started before the hooks were installed. A quick spike from an
///    idle session doesn't count (see `BusyTracker`).
///
/// It also collects terminal and app activity, so one snapshot answers
/// "is any work running?".
final class ClaudeMonitor {
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sleepable", isDirectory: true) // pre-rename name, kept so existing installs keep working
    }()

    static let sessionsDirectory = supportDirectory.appendingPathComponent("sessions", isDirectory: true)

    /// A marker untouched this long is ignored if no claude process is alive.
    private let orphanAge: TimeInterval = 20 * 60
    /// A marker untouched this long is always considered stale (crash, kill -9…).
    private let hardStaleAge: TimeInterval = 6 * 60 * 60
    private let cpuThreshold: Double = 3.0

    private let terminals = TerminalMonitor()
    private let apps = AppMonitor()
    private let network = NetworkMonitor()
    private let tracker = BusyTracker()

    func snapshot(
        useProcessHeuristic: Bool,
        watchTerminals: Bool,
        watchedApps: [(app: WorkApp, mode: WatchMode)],
        watchNetwork: Bool
    ) -> ClaudeActivity {
        var activity = ClaudeActivity()
        if watchNetwork { activity.transfer = network.activeTransfer() }
        if watchTerminals { activity.busyTerminals = terminals.busyTerminals() }
        let table = ProcessTable.read()
        activity.busyApps = apps.busyApps(watching: watchedApps, table: table)

        // The Claude Code CLI binary is called `claude` (lowercase). The
        // Claude desktop app is `Claude` and is deliberately not counted.
        let processes = table.entries.values.filter { $0.name == "claude" }
        activity.runningProcesses = processes.count
        let readings = Dictionary(uniqueKeysWithValues: processes.map { ("\($0.pid)", $0.cpu >= cpuThreshold) })
        let busy = tracker.update(useProcessHeuristic ? readings : [:])
        activity.busyProcesses = busy.count
        activity.activeSessions = activeSessionCount(anyClaudeAlive: !processes.isEmpty)
        return activity
    }

    private func activeSessionCount(anyClaudeAlive: Bool) -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let now = Date()
        var count = 0
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let age = now.timeIntervalSince(modified)
            if age > hardStaleAge || (!anyClaudeAlive && age > orphanAge) {
                try? fm.removeItem(at: file)
                continue
            }
            count += 1
        }
        return count
    }
}
