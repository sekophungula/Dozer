import SwiftUI

/// The panel that drops down from the menu bar icon.
struct MenuView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                StatusOrb(active: state.isHoldingAwake, enabled: state.enabled)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.statusTitle).font(.headline)
                    Text(state.statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            Toggle(isOn: $state.enabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sleepable").fontWeight(.semibold)
                    Text("Stay awake until all Claude tasks are done")
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

            HStack {
                Button("Setup…") { SetupWindowController.shared.show() }
                Spacer()
                Button("Quit Sleepable") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
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
            Image(systemName: enabled ? (active ? "cup.and.heat.waves.fill" : "cup.and.saucer") : "moon.zzz")
                .foregroundStyle(color)
                .font(.system(size: 15, weight: .semibold))
        }
    }

    private var color: Color {
        if !enabled { return .secondary }
        return active ? .orange : .accentColor
    }
}
