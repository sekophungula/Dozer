import AppKit
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

    /// The main toggle. On = keep the Mac awake while Claude is working.
    @Published var enabled: Bool { didSet { persist(); evaluate(); syncControl() } }
    /// Keep awake no matter what Claude is doing.
    @Published var forceAwake: Bool { didSet { persist(); evaluate() } }
    /// Also keep the display on (otherwise only the system stays awake).
    @Published var keepDisplayAwake: Bool { didSet { persist(); evaluate() } }
    /// Count busy `claude` CLI processes as work, in addition to hooks.
    @Published var useProcessHeuristic: Bool { didSet { persist(); evaluate() } }
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
            "notifyWhenDone": true,
            "graceSeconds": 60.0,
            "hasCompletedSetup": false,
        ])
        enabled = defaults.bool(forKey: "enabled")
        forceAwake = defaults.bool(forKey: "forceAwake")
        keepDisplayAwake = defaults.bool(forKey: "keepDisplayAwake")
        useProcessHeuristic = defaults.bool(forKey: "useProcessHeuristic")
        notifyWhenDone = defaults.bool(forKey: "notifyWhenDone")
        graceSeconds = defaults.double(forKey: "graceSeconds")
        hasCompletedSetup = defaults.bool(forKey: "hasCompletedSetup")
        loading = false
    }

    // MARK: Lifecycle

    func start() {
        refreshHookStatus()
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
        let snapshot = monitor.snapshot(useProcessHeuristic: useProcessHeuristic)
        activity = snapshot
        if snapshot.isWorking { lastActivityAt = Date() }

        let claudeActive = isClaudeActive
        let shouldHold = enabled && (forceAwake || claudeActive)

        let reason = forceAwake
            ? "Dozex: keep awake is on"
            : "Dozex: Claude is still working"
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
        if activity.isWorking { return "Claude is working" }
        if isClaudeActive { return "Claude finished" }
        return "Watching for Claude"
    }

    var statusDetail: String {
        var parts: [String] = []
        if activity.activeSessions > 0 {
            parts.append("\(activity.activeSessions) Claude Code task\(activity.activeSessions == 1 ? "" : "s") running")
        }
        if activity.busyProcesses > 0, activity.activeSessions == 0 {
            parts.append("\(activity.busyProcesses) busy claude process\(activity.busyProcesses == 1 ? "" : "es")")
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
        content.title = "Claude is done"
        content.body = forceAwake
            ? "All Claude tasks finished. Keep-awake is still on."
            : "All Claude tasks finished — your Mac can sleep again."
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
        defaults.set(notifyWhenDone, forKey: "notifyWhenDone")
        defaults.set(graceSeconds, forKey: "graceSeconds")
        defaults.set(hasCompletedSetup, forKey: "hasCompletedSetup")
    }
}
