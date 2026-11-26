import Foundation

/// One `ps` reading of every process: who started it, how much CPU it uses
/// and which executable it is. Shared by the Claude and app checks so each
/// round costs a single `ps` call.
struct ProcessTable {
    struct Entry {
        let pid: Int32
        let ppid: Int32
        let cpu: Double
        /// Full path of the executable, e.g. "/Applications/Final Cut Pro.app/Contents/MacOS/Final Cut Pro".
        let command: String
        var name: String { (command as NSString).lastPathComponent }
    }

    let entries: [Int32: Entry]
    private let children: [Int32: [Int32]]

    init(entries: [Entry]) {
        var byPID: [Int32: Entry] = [:]
        var children: [Int32: [Int32]] = [:]
        for e in entries {
            byPID[e.pid] = e
            children[e.ppid, default: []].append(e.pid)
        }
        self.entries = byPID
        self.children = children
    }

    /// CPU % of a process plus everything it started (render workers,
    /// encoders, build tools…).
    func treeCPU(of pid: Int32) -> Double {
        var total = 0.0
        var stack = [pid]
        var seen = Set<Int32>()
        while let next = stack.popLast(), seen.insert(next).inserted {
            total += entries[next]?.cpu ?? 0
            stack.append(contentsOf: children[next] ?? [])
        }
        return total
    }

    static func read() -> ProcessTable {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Ao", "pid=,ppid=,pcpu=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return ProcessTable(entries: []) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return ProcessTable(entries: []) }

        var result: [Entry] = []
        for line in output.split(separator: "\n") {
            // The command comes last and may contain spaces.
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2].replacingOccurrences(of: ",", with: "."))
            else { continue }
            result.append(Entry(pid: pid, ppid: ppid, cpu: cpu, command: String(parts[3])))
        }
        return ProcessTable(entries: result)
    }
}
