import Foundation

/// Spots work running in terminal windows (Terminal, iTerm, Ghostty, Warp,
/// VS Code, tmux panes…), so CLI agents and long commands keep the Mac awake
/// even without Claude Code hooks.
///
/// For each terminal (tty) it looks at the foreground job, the command you
/// are waiting on:
/// - **A regular command** (`npm run build`, `cargo test`, `rsync`…) counts
///   for as long as it runs.
/// - **Interactive programs** (CLI agents like `claude`, `codex`, `gemini`,
///   `aider`; editors, pagers, `ssh`, `tmux`, REPLs) sit open for hours while
///   idle, so they count only while they keep using CPU. A quick spike
///   (an idle agent redrawing its screen) doesn't count; see `BusyTracker`.
/// - **A shell prompt** means nothing is running.
final class TerminalMonitor {
    /// CPU % (summed over the terminal's processes) that counts as busy for
    /// interactive programs. An idle agent waiting for input sits near 0–1 %.
    private let cpuThreshold: Double = 3.0
    private let tracker = BusyTracker()

    static let shells: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "tcsh", "csh", "ksh", "nu", "xonsh", "elvish", "pwsh", "login",
    ]
    /// CLI coding agents. Counted only while busy.
    static let agents: Set<String> = [
        "claude", "codex", "gemini", "aider", "opencode", "cursor-agent", "amp", "goose", "qwen",
        "crush", "droid", "copilot", "kiro-cli", "cline", "continue", "plandex", "openhands",
    ]
    /// Other programs that stay open while idle. Counted only while busy.
    static let interactive: Set<String> = [
        "vim", "nvim", "vi", "nano", "emacs", "micro", "helix", "hx", "kak", "less", "more", "most", "man",
        "top", "htop", "btop", "atop", "glances", "watch", "ssh", "mosh", "mosh-client", "et", "tmux", "screen",
        "zellij", "lazygit", "tig", "ranger", "nnn", "lf", "yazi", "mc", "k9s", "psql", "mysql", "sqlite3",
        "redis-cli", "mongosh", "ipython", "bpython", "ptpython", "jshell", "ghci", "iex", "erl", "scala",
    ]
    /// Interpreters: a REPL when started without a script, otherwise a command.
    static let interpreters: Set<String> = [
        "node", "python", "python3", "ruby", "irb", "bun", "deno", "lua", "R", "julia", "php", "perl",
    ]

    struct BusyTerminal: Equatable {
        /// Short name of what's running, e.g. "npm" or "codex".
        let command: String
        let isAgent: Bool
    }

    /// One entry per terminal that's busy right now.
    func busyTerminals() -> [BusyTerminal] {
        var byTTY: [String: [Proc]] = [:]
        for p in Self.listProcesses() where p.tty != "??" && !p.tty.isEmpty {
            byTTY[p.tty, default: []].append(p)
        }
        var result: [BusyTerminal] = []
        var readings: [String: Bool] = [:]
        var gated: [String: BusyTerminal] = [:]
        for (tty, procs) in byTTY {
            guard let reading = Self.classify(procs, cpuThreshold: cpuThreshold) else { continue }
            if reading.cpuGated {
                // Key by tty and program, so a new program in the same tab starts fresh.
                let key = "\(tty) \(reading.terminal.command)"
                readings[key] = reading.hot
                gated[key] = reading.terminal
            } else {
                result.append(reading.terminal)
            }
        }
        for key in tracker.update(readings) {
            if let terminal = gated[key] { result.append(terminal) }
        }
        return result.sorted { $0.command < $1.command }
    }

    // MARK: - Classification

    struct Proc {
        let pid: Int32
        let stat: String
        let cpu: Double
        let tty: String
        let args: [String]
        /// "-/bin/zsh" → "zsh", "/usr/local/bin/node" → "node"
        var name: String { Self.baseName(args.first ?? "") }
        var isForeground: Bool { stat.contains("+") }

        static func baseName(_ s: String) -> String {
            var s = s
            if s.hasPrefix("-") { s.removeFirst() }
            return (s as NSString).lastPathComponent
        }
    }

    enum Kind { case shell, agent(String), interactive(String), command(String) }

    static func kind(of p: Proc) -> Kind {
        let name = p.name
        if shells.contains(name) { return .shell }
        if agents.contains(name) { return .agent(name) }
        if interpreters.contains(name) {
            // `node /opt/homebrew/bin/gemini` is an agent; `python3` alone is a REPL.
            let rest = p.args.dropFirst().filter { !$0.hasPrefix("-") }
            if let script = rest.first {
                let scriptName = Proc.baseName(script)
                if agents.contains(scriptName) { return .agent(scriptName) }
                return .command(name)
            }
            return .interactive(name)
        }
        if interactive.contains(name) { return .interactive(name) }
        return .command(name)
    }

    struct Reading {
        let terminal: BusyTerminal
        /// An agent or editor: busy only if it keeps using CPU across readings.
        let cpuGated: Bool
        /// For gated programs: above the CPU threshold right now.
        let hot: Bool
    }

    /// Reads what one terminal is doing, from all processes attached to it.
    /// Nil means it's sitting at a shell prompt.
    static func classify(_ procs: [Proc], cpuThreshold: Double) -> Reading? {
        let foreground = procs.filter(\.isForeground)
        var firstCommand: String?
        var interactiveName: String?
        var agentName: String?
        for p in foreground {
            switch kind(of: p) {
            case .shell: continue
            case .agent(let n): agentName = agentName ?? n
            case .interactive(let n): interactiveName = interactiveName ?? n
            case .command(let n): firstCommand = firstCommand ?? n
            }
        }
        // An agent or editor in front: busy only while it (or what it started) uses CPU.
        if let name = agentName ?? interactiveName {
            let cpu = procs.filter { kind(of: $0).isNotShell }.reduce(0) { $0 + $1.cpu }
            return Reading(terminal: BusyTerminal(command: name, isAgent: agentName != nil),
                           cpuGated: true, hot: cpu >= cpuThreshold)
        }
        if let name = firstCommand {
            return Reading(terminal: BusyTerminal(command: name, isAgent: false), cpuGated: false, hot: true)
        }
        return nil
    }

    // MARK: - ps

    private static func listProcesses() -> [Proc] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Ao", "pid=,stat=,pcpu=,tty=,args="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.split(separator: "\n").compactMap(parse)
    }

    static func parse(_ line: Substring) -> Proc? {
        let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count == 5,
              let pid = Int32(parts[0]),
              let cpu = Double(parts[2].replacingOccurrences(of: ",", with: "."))
        else { return nil }
        // Good enough for naming: paths with spaces only matter past the first word.
        let args = parts[4].split(separator: " ").map(String.init)
        return Proc(pid: pid, stat: String(parts[1]), cpu: cpu, tty: String(parts[3]), args: args)
    }
}

private extension TerminalMonitor.Kind {
    var isNotShell: Bool {
        if case .shell = self { return false }
        return true
    }
}
