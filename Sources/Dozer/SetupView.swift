import UniformTypeIdentifiers
import SwiftUI

/// The in-app landing page: what Dozer does and how to set it up.
struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var updater: Updater

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                VStack(spacing: 14) {
                    StepCard(number: 1, title: "Pick the apps to watch",
                             done: state.watchApps) { appsStep }
                    StepCard(number: 2, title: "Choose how Dozer behaves",
                             done: true) { optionsStep }
                    StepCard(number: 3, title: "Connect Claude Code (optional)",
                             done: state.hooksInstalled) { connectStep }
                    StepCard(number: 4, title: "Put the toggle where you want it",
                             done: true) { toggleStep }
                    StepCard(number: 5, title: "Start with your Mac",
                             done: state.launchAtLogin) { loginStep }
                    StepCard(number: 6, title: "Stay up to date",
                             done: updater.status == .upToDate) { updateStep }
                }

                if let error = state.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    state.hasCompletedSetup = true
                    SetupWindowController.shared.close()
                } label: {
                    Text(state.hasCompletedSetup ? "Close" : "Done — take me to the menu bar")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 36)
            .padding(.top, 44)
            .padding(.bottom, 28)
        }
        .frame(minWidth: 600, minHeight: 640)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.10), Color.indigo.opacity(0.10), Color.clear],
                startPoint: .top, endPoint: .center
            )
        )
        .onAppear {
            state.refreshHookStatus()
            state.refreshLaunchAtLogin()
            state.refreshInstalledApps()
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            Text("Dozer")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Your Mac stays awake while exports, renders, builds\nand AI agents run, then sleeps the moment they're done.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                StatusOrb(active: state.isHoldingAwake, enabled: state.enabled)
                Text(state.statusTitle).font(.callout.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
        }
    }

    // MARK: Steps

    private var appsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Stay awake while these apps are working", isOn: $state.watchApps)
                .toggleStyle(.switch)
            Text("No need to change your sleep settings or leave a video playing. Dozer notices when an app is busy, like Final Cut Pro exporting or Blender rendering, keeps your Mac awake until it finishes, then lets it sleep. Choose **While open** to stay awake the whole time an app is open.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                if state.appRows.isEmpty {
                    Text("None of the usual export and render apps are installed. Add the apps you use below.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                ForEach(Array(state.appRows.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Divider() }
                    AppRow(app: app)
                }
            }
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary))
            .disabled(!state.watchApps)
            .opacity(state.watchApps ? 1 : 0.5)

            Button {
                state.addCustomApp()
            } label: {
                Label("Add an app…", systemImage: "plus")
            }
            .disabled(!state.watchApps)
            Text("An app counts as busy once it has been working hard for about 15 seconds, so opening it or clicking around doesn't keep your Mac up.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If you use Claude Code, Dozer adds small hooks to Claude Code (`~/.claude/settings.json`) so it knows exactly when a task starts and when Claude stops. Your existing settings are kept and backed up first. Works for the Claude Code CLI and the Code tab in the Claude app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if state.hooksInstalled {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Disconnect") { state.uninstallHooks() }
                } else {
                    Button("Connect Claude Code") { state.installHooks() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
            Text("Already-running Claude sessions are picked up on their next prompt. Until then, Dozer also watches for busy `claude` processes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var optionsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Dozer is on (stay awake while work is running)", isOn: $state.enabled)
            Toggle("Keep the display on too, not just the computer", isOn: $state.keepDisplayAwake)
            Toggle("Also treat busy `claude` processes as work", isOn: $state.useProcessHeuristic)
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Stay awake while anything runs in a terminal", isOn: $state.watchTerminals)
                Text("Covers builds, scripts and CLI agents like Codex, Gemini and Aider in Terminal, iTerm, Ghostty, VS Code and others. Agents, editors and `ssh` only count while they keep working, so an idle session doesn't keep your Mac up.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Stay awake while files transfer", isOn: $state.watchTransfers)
                Text("Covers downloads and uploads in any app, network shares, cloud folders syncing, online backups, and copies to or from an external drive or SD card. Light traffic like music or messages doesn't count, and a transfer has to keep going for about 15 seconds.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            Toggle("Notify me when the work is done", isOn: $state.notifyWhenDone)
            HStack {
                Text("Stay awake after the work finishes for")
                Picker("", selection: $state.graceSeconds) {
                    Text("10 seconds").tag(10.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                }
                .labelsHidden()
                .frame(width: 130)
            }
        }
        .toggleStyle(.switch)
    }

    private var toggleStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("**Menu bar** — the eye icon at the top of your screen. Hold ⌘ and drag it to reorder.")
            } icon: { Image(systemName: "menubar.rectangle") }
            Label {
                Text("**Control Center** (macOS 26+) — open Control Center, click **Edit Controls**, search “Dozer” and drag it in. You can also pin it to the menu bar from there.")
            } icon: { Image(systemName: "switch.2") }
            Button("Open Control Center settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var updateStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                switch updater.status {
                case .available(let version):
                    Text("Version \(version) is available (you have \(updater.currentVersion)).")
                    Spacer()
                    Button("Update Now") { Task { await updater.installUpdate() } }
                        .buttonStyle(.borderedProminent)
                case .checking:
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                    Spacer()
                case .downloading, .installing:
                    ProgressView().controlSize(.small)
                    Text(updater.status == .downloading ? "Downloading…" : "Installing — Dozer will reopen.")
                    Spacer()
                case .upToDate:
                    Label("You're on the latest version (\(updater.currentVersion)).", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Check Again") { Task { await updater.check() } }
                case .failed(let message):
                    Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Try Again") { Task { await updater.check() } }
                case .idle:
                    Text("Version \(updater.currentVersion)")
                    Spacer()
                    Button("Check for Updates") { Task { await updater.check() } }
                }
            }
            .font(.callout)
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                .toggleStyle(.switch)
            Text("Updates come from this app's GitHub releases and install in place, wherever Dozer lives.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loginStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Open Dozer at login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            Text("Note: macOS always sleeps when you close a MacBook lid without an external display. Keep the lid open (or plugged into a monitor) for long runs.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One app in the watch list: icon, name and its setting.
struct AppRow: View {
    @EnvironmentObject private var state: AppState
    let app: WorkApp

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 22, height: 22)
            Text(app.name)
            Spacer()
            Picker("", selection: Binding(
                get: { state.mode(for: app) },
                set: { state.setMode($0, for: app) }
            )) {
                ForEach(WatchMode.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            if app.isCustom {
                Button {
                    state.removeCustomApp(app)
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Stop watching \(app.name)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var icon: NSImage {
        if let path = app.path, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.15))
                    .frame(width: 30, height: 30)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.green)
                } else {
                    Text("\(number)").font(.callout.bold()).foregroundStyle(Color.accentColor)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary)
        )
    }
}
