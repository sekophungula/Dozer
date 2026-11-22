import AppKit
import Foundation

/// Self-updater that installs new versions straight from GitHub Releases.
///
/// 1. Asks the GitHub API for the latest release and compares its tag with
///    the running version.
/// 2. Downloads the release's `Dozex.zip`, unpacks it and checks that the
///    bundle ID, version and code signature are what we expect.
/// 3. Swaps the new app into place (wherever Dozex is installed) and
///    relaunches.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    nonisolated static let repo = "sekophungula/Dozex"
    nonisolated static let assetName = "Dozex.zip"

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var latest: Release?
    @Published private(set) var lastChecked: Date?
    @Published var automaticallyChecks: Bool {
        didSet { UserDefaults.standard.set(automaticallyChecks, forKey: "automaticallyChecksForUpdates") }
    }

    struct Release: Equatable {
        let version: String
        let notes: String
        let pageURL: URL
        let zipURL: URL
    }

    let currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private var timer: Timer?

    private init() {
        UserDefaults.standard.register(defaults: ["automaticallyChecksForUpdates": true])
        automaticallyChecks = UserDefaults.standard.bool(forKey: "automaticallyChecksForUpdates")
    }

    var updateAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    /// Checks shortly after launch and then every 12 hours, if enabled.
    func startAutomaticChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.automaticallyChecks else { return }
            Task { await self.check(userInitiated: false) }
        }
        let timer = Timer(timeInterval: 12 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in
                let updater = Updater.shared
                if updater.automaticallyChecks { await updater.check(userInitiated: false) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Check

    func check(userInitiated: Bool = true) async {
        switch status {
        case .checking, .downloading, .installing: return
        default: break
        }
        status = .checking
        do {
            let release = try await fetchLatestRelease()
            latest = release
            lastChecked = Date()
            status = Self.isVersion(release.version, newerThan: currentVersion)
                ? .available(version: release.version)
                : .upToDate
        } catch {
            // Background checks fail quietly (offline, rate-limited…).
            status = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Dozex/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }

        struct APIRelease: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let body: String?
            let html_url: URL
            let assets: [Asset]
        }
        let api = try JSONDecoder().decode(APIRelease.self, from: data)
        guard let zip = api.assets.first(where: { $0.name == Self.assetName }) else { throw UpdateError.noAsset }
        let version = api.tag_name.hasPrefix("v") ? String(api.tag_name.dropFirst()) : api.tag_name
        return Release(version: version, notes: api.body ?? "", pageURL: api.html_url, zipURL: zip.browser_download_url)
    }

    // MARK: - Install

    func installUpdate() async {
        guard let release = latest, Self.isVersion(release.version, newerThan: currentVersion) else { return }
        do {
            status = .downloading
            let (zipFile, response) = try await URLSession.shared.download(from: release.zipURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }

            status = .installing
            let newApp = try await Task.detached(priority: .userInitiated) {
                try Self.unpackAndVerify(zipFile: zipFile, expectedVersion: release.version)
            }.value
            try Self.replaceRunningApp(with: newApp)
            relaunch()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    nonisolated private static func unpackAndVerify(zipFile: URL, expectedVersion: String) throws -> URL {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("DozexUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zipFile.path, workDir.path])

        let app = workDir.appendingPathComponent("Dozex.app")
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion
        else { throw UpdateError.invalidBundle }

        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        // Downloaded via URLSession, so no quarantine flag is expected, but
        // clear it anyway so the relaunch is never blocked.
        try? run("/usr/bin/xattr", ["-cr", app.path])
        return app
    }

    /// Where the app should live: next to the running copy, always named Dozex.app.
    private static var preferredBundleURL: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Dozex.app")
    }

    /// Where the freshly installed copy ends up, so relaunch opens the right one.
    private static var installedBundleURL: URL?

    private static func replaceRunningApp(with newApp: URL) throws {
        let fm = FileManager.default
        let installed = Bundle.main.bundleURL
        let parent = installed.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable(parent.path)
        }
        // Copies from before the rename live at Sleepable.app; install the new
        // one as Dozex.app unless something else already has that name.
        var target = preferredBundleURL
        if target != installed, fm.fileExists(atPath: target.path) { target = installed }

        // Keep the old copy until the new one is in place, so a failure can
        // be rolled back.
        let backup = parent.appendingPathComponent(".Dozex-old-\(UUID().uuidString).app")
        try fm.moveItem(at: installed, to: backup)
        do {
            try fm.moveItem(at: newApp, to: target)
        } catch {
            try? fm.moveItem(at: backup, to: installed)
            throw error
        }
        try? fm.removeItem(at: backup)
        installedBundleURL = target
    }

    /// Dozex used to be called Sleepable. Updating from 1.1.0 or older leaves
    /// the app at Sleepable.app, so rename it once and reopen.
    /// Returns true when it relaunched.
    func renameLegacyBundleIfNeeded() -> Bool {
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        let target = Self.preferredBundleURL
        guard current.lastPathComponent == "Sleepable.app",
              !fm.fileExists(atPath: target.path),
              fm.isWritableFile(atPath: current.deletingLastPathComponent().path),
              (try? fm.moveItem(at: current, to: target)) != nil
        else { return false }
        Self.installedBundleURL = target
        relaunch()
        return true
    }

    private func relaunch() {
        let path = (Self.installedBundleURL ?? Bundle.main.bundleURL).path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    nonisolated private static func run(_ tool: String, _ args: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw UpdateError.toolFailed((tool as NSString).lastPathComponent)
        }
    }

    /// Numeric, component-wise comparison: 1.10.0 > 1.9.3.
    nonisolated static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    enum UpdateError: LocalizedError {
        case badResponse, noAsset, invalidBundle
        case notWritable(String)
        case toolFailed(String)

        var errorDescription: String? {
            switch self {
            case .badResponse: return "Couldn't reach GitHub. Check your connection and try again."
            case .noAsset: return "The latest release doesn't include \(Updater.assetName)."
            case .invalidBundle: return "The downloaded update didn't look like Dozex, so it wasn't installed."
            case .notWritable(let path): return "Dozex can't write to \(path). Download the update from GitHub instead."
            case .toolFailed(let tool): return "Installing the update failed (\(tool))."
            }
        }
    }
}
