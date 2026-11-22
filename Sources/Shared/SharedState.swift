import Foundation

/// State shared between the Dozex app and its Control Center extension.
///
/// The extension is sandboxed, so the file lives inside the extension's own
/// container; the (unsandboxed) app reads and writes it there. Each side
/// posts a Darwin notification after writing so the other can react.
enum SharedState {
    static let appBundleID = "io.github.sekophungula.sleepable"
    static let controlBundleID = "io.github.sekophungula.sleepable.control"
    static let controlKind = "io.github.sekophungula.sleepable.toggle"

    static let toggledByControl = "io.github.sekophungula.sleepable.control-toggled"
    static let changedByApp = "io.github.sekophungula.sleepable.app-changed"

    struct Payload: Codable {
        var enabled: Bool
        var holding: Bool
    }

    /// The file URL, as seen by whichever process is calling.
    static var fileURL: URL {
        if Bundle.main.bundleIdentifier == controlBundleID {
            // Inside the sandbox, the home directory *is* the container.
            return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("sleepable-state.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(controlBundleID)/Data/sleepable-state.json")
    }

    static func read() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Writes the payload. The app only writes when the extension's container
    /// already exists (i.e. the control has been added at least once).
    @discardableResult
    static func write(_ payload: Payload) -> Bool {
        let dir = fileURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: dir.path),
              let data = try? JSONEncoder().encode(payload)
        else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }
}
