import Foundation

/// Installs / removes the Claude Code hooks that tell Sleepable when a task
/// starts and finishes. Edits `~/.claude/settings.json` non-destructively:
/// existing settings and hooks are preserved, and a backup is written the
/// first time Sleepable touches the file.
enum HookInstaller {
    static let scriptName = "sleepable-hook.sh"
    static var scriptURL: URL { ClaudeMonitor.supportDirectory.appendingPathComponent(scriptName) }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// Claude Code hook event → argument passed to the script.
    static let events: [(event: String, action: String)] = [
        ("UserPromptSubmit", "start"),
        ("PreToolUse", "touch"),
        ("PostToolUse", "touch"),
        ("Stop", "stop"),
        ("SessionEnd", "stop"),
    ]

    static let script = """
    #!/bin/sh
    # Sleepable hook for Claude Code — https://github.com/sekophungula/Sleepable
    # Marks a Claude Code session as busy (start/touch) or finished (stop).
    dir="$HOME/Library/Application Support/Sleepable/sessions"
    mkdir -p "$dir"
    input=$(cat)
    sid=$(printf '%s' "$input" | tr -d '\\n' | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p')
    [ -z "$sid" ] && sid="unknown"
    sid=$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9._-')
    case "$1" in
      start|touch) touch "$dir/$sid" ;;
      stop) rm -f "$dir/$sid" ;;
    esac
    exit 0
    """

    static func command(for action: String) -> String {
        "'\(scriptURL.path)' \(action)"
    }

    // MARK: - Status

    static func isInstalled() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path),
              let hooks = (try? readSettings())?["hooks"] as? [String: Any]
        else { return false }
        return events.allSatisfy { entry in
            guard let groups = hooks[entry.event] as? [[String: Any]] else { return false }
            return groups.contains(where: isSleepableGroup)
        }
    }

    // MARK: - Install / uninstall

    static func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: ClaudeMonitor.sessionsDirectory, withIntermediateDirectories: true)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var settings = try readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for entry in events {
            var groups = (hooks[entry.event] as? [[String: Any]] ?? []).filter { !isSleepableGroup($0) }
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": command(for: entry.action),
                    "timeout": 5,
                ]],
            ])
            hooks[entry.event] = groups
        }
        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    static func uninstall() throws {
        if var settings = try readSettings(), var hooks = settings["hooks"] as? [String: Any] {
            for entry in events {
                guard let groups = hooks[entry.event] as? [[String: Any]] else { continue }
                let kept = groups.filter { !isSleepableGroup($0) }
                hooks[entry.event] = kept.isEmpty ? nil : kept
            }
            settings["hooks"] = hooks.isEmpty ? nil : hooks
            try writeSettings(settings)
        }
        try? FileManager.default.removeItem(at: scriptURL)
        try? FileManager.default.removeItem(at: ClaudeMonitor.sessionsDirectory)
    }

    // MARK: - Helpers

    private static func isSleepableGroup(_ group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String)?.contains(scriptName) == true }
    }

    private static func readSettings() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableSettings
        }
        return object
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = settingsURL.appendingPathExtension("sleepable-backup")
        if fm.fileExists(atPath: settingsURL.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    enum InstallError: LocalizedError {
        case unreadableSettings
        var errorDescription: String? {
            "~/.claude/settings.json isn't valid JSON, so Sleepable left it untouched. Fix the file and try again."
        }
    }
}
