import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / menu bar control for Sleepable (macOS 26+).
@main
struct SleepableControlBundle: WidgetBundle {
    var body: some Widget {
        SleepableToggleControl()
    }
}

struct SleepableToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SharedState.controlKind, provider: Provider()) { isOn in
            ControlWidgetToggle("Sleepable", isOn: isOn, action: SetSleepableIntent()) { on in
                Label(on ? "Awake for Claude" : "Off",
                      systemImage: on ? "cup.and.heat.waves.fill" : "moon.zzz")
            }
            .tint(.orange)
        }
        .displayName("Sleepable")
        .description("Keep your Mac awake until all Claude tasks are done.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { true }

        func currentValue() async throws -> Bool {
            SharedState.read()?.enabled ?? true
        }
    }
}

struct SetSleepableIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Sleepable"
    static let description = IntentDescription("Turn Sleepable on or off.")

    @Parameter(title: "Sleepable is on")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        let holding = SharedState.read()?.holding ?? false
        _ = SharedState.write(.init(enabled: value, holding: holding))
        SharedState.post(SharedState.toggledByControl)
        return .result()
    }
}
