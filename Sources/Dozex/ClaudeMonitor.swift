import Foundation

/// What Dozex currently knows about Claude.
struct ClaudeActivity: Equatable {
    /// Claude Code sessions that are mid-task (reported by the hooks).
    var activeSessions: Int = 0
    /// `claude` CLI processes currently burning CPU (heuristic fallback).
    var busyProcesses: Int = 0
    /// Any `claude` CLI process running at all, busy or not.
    var runningProcesses: Int = 0

    var isWorking: Bool { activeSessions > 0 || busyProcesses > 0 }
}

/// Detects whether Claude is working, using two signals:
///
/// 1. **Hooks (precise).** Dozex installs Claude Code hooks that drop a
///    marker file per session when a prompt is submitted / a tool runs, and
///    delete it when Claude stops. A marker present = a task in flight.
/// 2. **Process heuristic (fallback).** Any `claude` CLI process using more
///    than a little CPU counts as working, which covers sessions that
///    started before the hooks were installed.
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

    func snapshot(useProcessHeuristic: Bool) -> ClaudeActivity {
        var activity = ClaudeActivity()
        let processes = claudeProcesses()
        activity.runningProcesses = processes.count
        if useProcessHeuristic {
            activity.busyProcesses = processes.filter { $0.cpu >= cpuThreshold }.count
        }
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

    private struct ProcessInfoLite { let pid: Int32; let cpu: Double }

    /// Lists `claude` CLI processes with their recent CPU usage via `ps`.
    private func claudeProcesses() -> [ProcessInfoLite] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Ao", "pid=,pcpu=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var result: [ProcessInfoLite] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1].replacingOccurrences(of: ",", with: "."))
            else { continue }
            let name = (String(parts[2]) as NSString).lastPathComponent
            // The Claude Code CLI binary is called `claude` (lowercase). The
            // Claude desktop app is `Claude` and is deliberately not counted.
            if name == "claude" {
                result.append(ProcessInfoLite(pid: pid, cpu: cpu))
            }
        }
        return result
    }
}
