import AppKit

/// An app Dozer can watch: a known creative/dev app, or one the user added.
struct WorkApp: Codable, Hashable, Identifiable {
    /// Bundle identifier. For known apps it's a prefix, so
    /// "com.adobe.PremierePro" matches "com.adobe.PremierePro.25".
    let id: String
    let name: String
    /// Where it's installed, for the icon. Filled in by `scanInstalled`.
    var path: String?
    var isCustom = false

    func matches(bundleID: String) -> Bool {
        isCustom ? bundleID == id : bundleID == id || bundleID.hasPrefix(id)
    }
}

/// How an app keeps the Mac awake.
enum WatchMode: String, Codable, CaseIterable, Identifiable {
    /// Ignored.
    case off
    /// While it's working hard (exporting, rendering, building…).
    case whenBusy
    /// The whole time it's open.
    case whileOpen

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .whenBusy: "When busy"
        case .whileOpen: "While open"
        }
    }
}

/// Spots apps doing long jobs (Final Cut Pro exporting, Blender rendering,
/// HandBrake encoding, Xcode building…) by watching their CPU use, including
/// any helper processes they start.
final class AppMonitor {
    /// Apps that commonly run long exports, renders or builds. Each is
    /// watched only when installed and open.
    static let catalog: [WorkApp] = [
        // Video
        WorkApp(id: "com.apple.FinalCut", name: "Final Cut Pro"),
        WorkApp(id: "com.apple.Compressor", name: "Compressor"),
        WorkApp(id: "com.apple.motionapp", name: "Motion"),
        WorkApp(id: "com.apple.iMovieApp", name: "iMovie"),
        WorkApp(id: "com.adobe.PremierePro", name: "Adobe Premiere Pro"),
        WorkApp(id: "com.adobe.ame", name: "Adobe Media Encoder"),
        WorkApp(id: "com.adobe.AfterEffects", name: "Adobe After Effects"),
        WorkApp(id: "com.blackmagic-design.DaVinciResolve", name: "DaVinci Resolve"),
        WorkApp(id: "fr.handbrake.HandBrake", name: "HandBrake"),
        // Audio
        WorkApp(id: "com.apple.logic10", name: "Logic Pro"),
        WorkApp(id: "com.apple.garageband10", name: "GarageBand"),
        WorkApp(id: "com.ableton.live", name: "Ableton Live"),
        WorkApp(id: "com.avid.ProTools", name: "Pro Tools"),
        // Photo, 3D and games
        WorkApp(id: "com.adobe.Photoshop", name: "Adobe Photoshop"),
        WorkApp(id: "com.adobe.LightroomClassic", name: "Lightroom Classic"),
        WorkApp(id: "com.adobe.lightroomCC", name: "Lightroom"),
        WorkApp(id: "org.blenderfoundation.blender", name: "Blender"),
        WorkApp(id: "com.maxon.cinema4d", name: "Cinema 4D"),
        WorkApp(id: "com.unity3d.UnityEditor", name: "Unity"),
        WorkApp(id: "com.epicgames.UnrealEditor", name: "Unreal Editor"),
        // Development
        WorkApp(id: "com.apple.dt.Xcode", name: "Xcode"),
        WorkApp(id: "com.google.android.studio", name: "Android Studio"),
    ]

    struct BusyApp: Equatable {
        let name: String
        /// Counted because it's set to "While open", not because it's busy.
        let openOnly: Bool
    }

    /// CPU % (app plus its helpers) that counts as working. An app sitting
    /// open with a project loaded stays well under this; an export or render
    /// uses far more.
    private let cpuThreshold: Double = 10.0
    private let tracker = BusyTracker()

    func busyApps(watching list: [(app: WorkApp, mode: WatchMode)], table: ProcessTable) -> [BusyApp] {
        let watched = list.filter { $0.mode != .off }
        guard !watched.isEmpty else { _ = tracker.update([:]); return [] }

        var result: [BusyApp] = []
        var readings: [String: Bool] = [:]
        var names: [String: String] = [:]
        for running in NSWorkspace.shared.runningApplications {
            guard let bundleID = running.bundleIdentifier,
                  let match = watched.first(where: { $0.app.matches(bundleID: bundleID) })
            else { continue }
            let name = running.localizedName ?? match.app.name
            if match.mode == .whileOpen {
                result.append(BusyApp(name: name, openOnly: true))
            } else {
                let key = "\(running.processIdentifier)"
                readings[key] = table.treeCPU(of: running.processIdentifier) >= cpuThreshold
                names[key] = name
            }
        }
        for key in tracker.update(readings) {
            if let name = names[key] { result.append(BusyApp(name: name, openOnly: false)) }
        }
        // Busy apps first, then alphabetical; one entry per name.
        var seen = Set<String>()
        return result
            .sorted { ($0.openOnly ? 1 : 0, $0.name) < ($1.openOnly ? 1 : 0, $1.name) }
            .filter { seen.insert($0.name).inserted }
    }

    /// The known apps installed on this Mac, with their locations.
    static func scanInstalled() -> [WorkApp] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var folders = ["/Applications", "/Applications/Utilities", "\(home)/Applications"]
        // Adobe and others install into a folder: /Applications/Adobe Premiere Pro 2025/…
        if let items = try? fm.contentsOfDirectory(atPath: "/Applications") {
            folders += items.filter { !$0.hasSuffix(".app") && !$0.hasPrefix(".") }.map { "/Applications/\($0)" }
        }

        var found: [String: WorkApp] = [:]
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = "\(folder)/\(item)"
                guard let bundleID = Bundle(path: path)?.bundleIdentifier,
                      var app = catalog.first(where: { $0.matches(bundleID: bundleID) }),
                      found[app.id] == nil
                else { continue }
                app.path = path
                found[app.id] = app
            }
        }
        return catalog.compactMap { found[$0.id] }
    }

    /// Builds a custom entry from an app the user picked.
    static func customApp(at url: URL) -> WorkApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return WorkApp(id: bundleID, name: name, path: url.path, isCustom: true)
    }
}
