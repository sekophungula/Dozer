import SwiftUI

/// The panel that drops down from the menu bar icon.
struct MenuView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .available(let version) = updater.status {
                UpdateBanner(text: "Dozex \(version) is available", buttonTitle: "Update") {
                    Task { await updater.installUpdate() }
                }
            } else if updater.status == .downloading || updater.status == .installing {
                UpdateBanner(text: updater.status == .downloading ? "Downloading update…" : "Installing update…",
                             buttonTitle: nil, action: {})
            }

            HStack(spacing: 10) {
                StatusOrb(active: state.isHoldingAwake, enabled: state.enabled)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.statusTitle)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(state.statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            Toggle(isOn: $state.enabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dozex").fontWeight(.semibold)
                    Text("Stay awake until Claude and Terminal are done")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $state.forceAwake) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep awake indefinitely")
                    Text("Ignore Claude and never sleep")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(!state.enabled)

            Toggle(isOn: $state.watchTerminals) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Watch Terminal")
                    Text("Stay awake while commands and CLI agents run")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(!state.enabled)

            Toggle("Keep display on too", isOn: $state.keepDisplayAwake)
                .toggleStyle(.switch)
                .disabled(!state.enabled)

            if !state.hooksInstalled {
                Button {
                    state.installHooks()
                } label: {
                    Label("Connect Claude Code for precise tracking", systemImage: "link")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }

            Divider()

            switch updater.status {
            case .checking:
                Text("Checking for updates…").font(.caption).foregroundStyle(.secondary)
            case .upToDate:
                Text("You're on the latest version (\(updater.currentVersion)).")
                    .font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }

            HStack(spacing: 14) {
                Button("Setup…") { SetupWindowController.shared.show() }
                Button("Check for Updates") { Task { await updater.check() } }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct UpdateBanner: View {
    let text: String
    let buttonTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
            Text(text)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let buttonTitle {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct StatusOrb: View {
    let active: Bool
    let enabled: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 34, height: 34)
            Image(nsImage: EyeIcon.image(enabled ? (active ? .awake : .dozing) : .off, size: 18))
                .renderingMode(.template)
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        if !enabled { return .secondary }
        return active ? .orange : .accentColor
    }
}
