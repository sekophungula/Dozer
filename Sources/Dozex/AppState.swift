import AppKit
import UniformTypeIdentifiers
import Combine
import ServiceManagement
import SwiftUI
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: Settings (persisted)

    /// The main toggle. On = keep the Mac awake while work is running.
    @Published var enabled: Bool { didSet { persist(); evaluate(); syncControl() } }
    /// Keep awake no matter what Claude is doing.
    @Published var forceAwake: Bool { didSet { persist(); evaluate() } }
    /// Also keep the display on (otherwise only the system stays awake).
    @Published var keepDisplayAwake: Bool { didSet { persist(); evaluate() } }
    /// Count busy `claude` CLI processes as work, in addition to hooks.
    @Published var useProcessHeuristic: Bool { didSet { persist(); evaluate() } }
    /// Stay awake while a command or CLI agent is running in any terminal.
    @Published var watchTerminals: Bool { didSet { persist(); evaluate() } }
    /// Stay awake while watched apps (Final Cut Pro, Blender, Xcode…) are working.
    @Published var watchApps: Bool { didSet { persist(); evaluate() } }
    /// Stay awake while a big download or upload is running.
    @Published var watchNetwork: Bool { didSet { persist(); evaluate() } }
    /// Per-app setting, keyed by `WorkApp.id`. Missing = "When busy".
    @Published var appModes: [String: WatchMode] { didSet { persist(); evaluate() } }
    /// Apps the user added themselves.
    @Published var customApps: [WorkApp] { didSet { persist(); evaluate() } }
    /// Post a notification when Claude finishes and sleep is allowed again.
    @Published var notifyWhenDone: Bool { didSet { persist(); if notifyWhenDone { requestNotificationPermission() } } }
    /// Seconds to stay awake after the last sign of Claude activity.
    @Published var graceSeconds: Double { didSet { persist() } }
    @Published var hasCompletedSetup: Bool { didSet { persist() } }

    // MARK: Live status

    @Published private(set) var activity = ClaudeActivity()
    @Published private(set) var isHoldingAwake = false
    @Published private(set) var lastActivityAt: Date?
    @Published private(set) var awakeSince: Date?
    @Published private(set) var hooksInstalled = false
    @Published var lastError: String?
    @Published private(set) var launchAtLogin = false
    /// Known apps found on this Mac, for the settings list.
    @Published private(set) var installedApps: [WorkApp] = []

    private let monitor = ClaudeMonitor()
    private let assertion = PowerAssertion()
    private var timer: Timer?
    private var wasClaudeActive = false
    private let defaults = UserDefaults.standard
    private var loading = true

    private init() {
        defaults.register(defaults: [
            "enabled": true,
            "forceAwake": false,
            "keepDisplayAwake": false,
            "useProcessHeuristic": true,
            "watchTerminals": true,
            "watchApps": true,
            "watchNetwork": true,
            "notifyWhenDone": true,
            "graceSeconds": 60.0,
            "hasCompletedSetup": false,
        ])
        enabled = defaults.bool(forKey: "enabled")
        forceAwake = defaults.bool(forKey: "forceAwake")
        keepDisplayAwake = defaults.bool(forKey: "keepDisplayAwake")
        useProcessHeuristic = defaults.bool(forKey: "useProcessHeuristic")
        watchTerminals = defaults.bool(forKey: "watchTerminals")
        watchApps = defaults.bool(forKey: "watchApps")
        watchNetwork = defaults.bool(forKey: "watchNetwork")
        appModes = (defaults.dictionary(forKey: "appModes") as? [String: String] ?? [:])
            .compactMapValues(WatchMode.init(rawValue:))
        customApps = defaults.data(forKey: "customApps")
            .flatMap { try? JSONDecoder().decode([WorkApp].self, from: $0) } ?? []
        notifyWhenDone = defaults.bool(forKey: "notifyWhenDone")
        graceSeconds = defaults.double(forKey: "graceSeconds")
        hasCompletedSetup = defaults.bool(forKey: "hasCompletedSetup")
        loading = false
    }

    // MARK: Lifecycle

    func start() {
        refreshHookStatus()
        refreshInstalledApps()
        refreshLaunchAtLogin()
        listenForControlCenter()
        evaluate()
        syncControl()
        let timer = Timer(timeInterval: 3, repeats: true) { _ in
            Task { @MainActor in AppState.shared.evaluate() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func shutdown() {
        timer?.invalidate()
        assertion.releaseAll()
    }

    // MARK: Core loop

    var isClaudeActive: Bool {
        if activity.isWorking { return true }
        guard let last = lastActivityAt else { return false }
        return Date().timeIntervalSince(last) < graceSeconds
    }

    func evaluate() {
        guard !loading else { return }
        let snapshot = monitor.snapshot(
            useProcessHeuristic: useProcessHeuristic,
            watchTerminals: watchTerminals,
            watchedApps: watchApps ? watchList : [],
            watchNetwork: watchNetwork
        )
        activity = snapshot
        if snapshot.isWorking { lastActivityAt = Date() }

        let claudeActive = isClaudeActive
        let shouldHold = enabled && (forceAwake || claudeActive)

        let reason: String
        if forceAwake {
            reason = "Dozex: keep awake is on"
        } else if snapshot.isClaudeWorking {
            reason = "Dozex: Claude is still working"
        } else if let app = snapshot.busyApps.first {
            reason = "Dozex: \(app.name) is \(app.openOnly ? "open" : "still working")"
        } else if !snapshot.busyTerminals.isEmpty {
            reason = "Dozex: a terminal command is still running"
        } else if let transfer = snapshot.transfer {
            reason = "Dozex: \(transfer.isUpload ? "an upload" : "a download") is still running"
        } else {
            reason = "Dozex: waiting a moment after work finished"
        }
        assertion.update(holdSystem: shouldHold, holdDisplay: keepDisplayAwake, reason: reason)

        if shouldHold != isHoldingAwake {
            isHoldingAwake = shouldHold
            awakeSince = shouldHold ? Date() : nil
            syncControl()
        }

        if wasClaudeActive, !claudeActive, enabled, notifyWhenDone {
            postDoneNotification()
        }
        wasClaudeActive = claudeActive
    }

    // MARK: Presentation helpers

    var menuBarIcon: EyeIcon.Style {
        if !enabled { return .off }
        return isHoldingAwake ? .awake : .dozing
    }

    var statusTitle: String {
        if !enabled { return "Dozex is off" }
        if forceAwake { return "Staying awake" }
        if activity.isClaudeWorking { return "Claude is working" }
        if let app = activity.busyApps.first {
            return app.openOnly ? "\(app.name) is open" : "\(app.name) is working"
        }
        if let first = activity.busyTerminals.first {
            return first.isAgent ? "\(first.command) is working" : "Terminal is busy"
        }
        if let transfer = activity.transfer { return transfer.isUpload ? "Uploading" : "Downloading" }
        if isClaudeActive { return "Work finished" }
        return "Watching for work"
    }

    /// "Final Cut Pro, HandBrake" — watched apps that are working or open.
    private var appSummary: String {
        let names = activity.busyApps.map(\.name)
        return names.prefix(2).joined(separator: ", ") + (names.count > 2 ? " +\(names.count - 2)" : "")
    }

    /// "npm, codex" — what's running in terminals, deduplicated.
    private var terminalSummary: String {
        var seen = Set<String>()
        let names = activity.busyTerminals.map(\.command).filter { seen.insert($0).inserted }
        return names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : "")
    }

    var statusDetail: String {
        var parts: [String] = []
        if activity.activeSessions > 0 {
            parts.append("\(activity.activeSessions) Claude Code task\(activity.activeSessions == 1 ? "" : "s") running")
        }
        if activity.busyProcesses > 0, activity.activeSessions == 0 {
            parts.append("\(activity.busyProcesses) busy claude process\(activity.busyProcesses == 1 ? "" : "es")")
        }
        if !activity.busyApps.isEmpty {
            let allOpen = activity.busyApps.allSatisfy(\.openOnly)
            parts.append("\(appSummary) \(allOpen ? "open" : "working")")
        }
        if !activity.busyTerminals.isEmpty {
            parts.append("\(terminalSummary) running in Terminal")
        }
        if let transfer = activity.transfer {
            let verb = transfer.isUpload ? "uploading" : "downloading"
            parts.append(parts.isEmpty ? NetworkMonitor.format(transfer.rate) : "\(verb) \(NetworkMonitor.format(transfer.rate))")
        }
        if parts.isEmpty {
            if !enabled {
                parts.append("Mac sleeps normally")
            } else if forceAwake {
                parts.append("Until you turn it off")
            } else if isClaudeActive, let last = lastActivityAt {
                let remaining = max(0, Int(graceSeconds - Date().timeIntervalSince(last)))
                parts.append("Sleep allowed in \(Self.shortDuration(TimeInterval(remaining)))")
            } else {
                parts.append("Mac can sleep when idle")
            }
        }
        if let since = awakeSince {
            parts.append("awake \(Self.shortDuration(Date().timeIntervalSince(since)))")
        }
        return parts.joined(separator: " · ")
    }

    private static func shortDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = seconds < 60 ? [.second] : [.hour, .minute]
        return formatter.string(from: seconds) ?? ""
    }

    // MARK: Watched apps

    /// Every app Dozex could watch, with its setting: the known apps plus
    /// the ones the user added.
    var watchList: [(app: WorkApp, mode: WatchMode)] {
        (AppMonitor.catalog + customApps).map { ($0, appModes[$0.id] ?? .whenBusy) }
    }

    /// The rows for the settings list: known apps that are installed, then added ones.
    var appRows: [WorkApp] { installedApps + customApps }

    func mode(for app: WorkApp) -> WatchMode { appModes[app.id] ?? .whenBusy }

    func setMode(_ mode: WatchMode, for app: WorkApp) { appModes[app.id] = mode }

    func refreshInstalledApps() { installedApps = AppMonitor.scanInstalled() }

    /// Asks for an app in /Applications and starts watching it.
    func addCustomApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app for Dozex to watch"
        panel.prompt = "Watch"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let app = AppMonitor.customApp(at: url) else { continue }
            if appRows.contains(where: { $0.id == app.id || $0.matches(bundleID: app.id) }) {
                // Already listed: just make sure it's on.
                if let existing = appRows.first(where: { $0.matches(bundleID: app.id) }), mode(for: existing) == .off {
                    setMode(.whenBusy, for: existing)
                }
                continue
            }
            customApps.append(app)
        }
    }

    func removeCustomApp(_ app: WorkApp) {
        customApps.removeAll { $0.id == app.id }
        appModes[app.id] = nil
    }

    // MARK: Hooks

    func refreshHookStatus() { hooksInstalled = HookInstaller.isInstalled() }

    func installHooks() {
        do {
            try HookInstaller.install()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refreshHookStatus()
    }

    func uninstallHooks() {
        do {
            try HookInstaller.uninstall()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refreshHookStatus()
    }

    // MARK: Launch at login

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = "Couldn't change Login Items: \(error.localizedDescription). Move Dozex to /Applications and try again."
        }
        refreshLaunchAtLogin()
    }

    // MARK: Control Center bridge

    private func listenForControlCenter() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { AppState.shared.controlCenterToggled() }
                }
            },
            SharedState.toggledByControl as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func controlCenterToggled() {
        guard let payload = SharedState.read(), payload.enabled != enabled else { return }
        enabled = payload.enabled
    }

    private func syncControl() {
        guard !loading else { return }
        SharedState.write(.init(enabled: enabled, holding: isHoldingAwake))
        SharedState.post(SharedState.changedByApp)
        #if canImport(WidgetKit)
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadControls(ofKind: SharedState.controlKind)
        }
        #endif
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postDoneNotification() {
        let content = UNMutableNotificationContent()
        content.title = "All done"
        content.body = forceAwake
            ? "Everything Dozex was watching has finished. Keep-awake is still on."
            : "Everything Dozex was watching has finished, so your Mac can sleep again."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Persistence

    private func persist() {
        guard !loading else { return }
        defaults.set(enabled, forKey: "enabled")
        defaults.set(forceAwake, forKey: "forceAwake")
        defaults.set(keepDisplayAwake, forKey: "keepDisplayAwake")
        defaults.set(useProcessHeuristic, forKey: "useProcessHeuristic")
        defaults.set(watchTerminals, forKey: "watchTerminals")
        defaults.set(watchApps, forKey: "watchApps")
        defaults.set(watchNetwork, forKey: "watchNetwork")
        defaults.set(appModes.mapValues(\.rawValue), forKey: "appModes")
        defaults.set(try? JSONEncoder().encode(customApps), forKey: "customApps")
        defaults.set(notifyWhenDone, forKey: "notifyWhenDone")
        defaults.set(graceSeconds, forKey: "graceSeconds")
        defaults.set(hasCompletedSetup, forKey: "hasCompletedSetup")
    }
}
