import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / menu bar control for Dozer (macOS 26+).
@main
struct DozerControlBundle: WidgetBundle {
    var body: some Widget {
        DozerToggleControl()
    }
}

struct DozerToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SharedState.controlKind, provider: Provider()) { isOn in
            ControlWidgetToggle("Dozer", isOn: isOn, action: SetDozerIntent()) { on in
                Label(on ? "Awake for Claude" : "Off",
                      systemImage: on ? "eye" : "moon.zzz")
            }
            .tint(.orange)
        }
        .displayName("Dozer")
        .description("Keep your Mac awake until all Claude tasks are done.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { true }

        func currentValue() async throws -> Bool {
            SharedState.read()?.enabled ?? true
        }
    }
}

struct SetDozerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Dozer"
    static let description = IntentDescription("Turn Dozer on or off.")

    @Parameter(title: "Dozer is on")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        let holding = SharedState.read()?.holding ?? false
        _ = SharedState.write(.init(enabled: value, holding: holding))
        SharedState.post(SharedState.toggledByControl)
        return .result()
    }
}
