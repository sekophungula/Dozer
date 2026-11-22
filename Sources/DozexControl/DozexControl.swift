import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / menu bar control for Dozex (macOS 26+).
@main
struct DozexControlBundle: WidgetBundle {
    var body: some Widget {
        DozexToggleControl()
    }
}

struct DozexToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SharedState.controlKind, provider: Provider()) { isOn in
            ControlWidgetToggle("Dozex", isOn: isOn, action: SetDozexIntent()) { on in
                Label(on ? "Awake for Claude" : "Off",
                      systemImage: on ? "eye" : "moon.zzz")
            }
            .tint(.orange)
        }
        .displayName("Dozex")
        .description("Keep your Mac awake until all Claude tasks are done.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { true }

        func currentValue() async throws -> Bool {
            SharedState.read()?.enabled ?? true
        }
    }
}

struct SetDozexIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Dozex"
    static let description = IntentDescription("Turn Dozex on or off.")

    @Parameter(title: "Dozex is on")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        let holding = SharedState.read()?.holding ?? false
        _ = SharedState.write(.init(enabled: value, holding: holding))
        SharedState.post(SharedState.toggledByControl)
        return .result()
    }
}
