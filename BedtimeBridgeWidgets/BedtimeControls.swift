import AppIntents
import SwiftUI
import WidgetKit

/// Controls for the Lock Screen's bottom buttons, Control Center and the Action button
/// (v0.4.3 item 16).

/// "Nap": opens the nap screen, or naps with the default length straight away (Settings →
/// Shortcuts & controls).
struct NapControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.bedtimebridge.control.nap") {
            ControlWidgetButton(action: NapControlIntent()) { Label("Nap", systemImage: "powersleep") }
        }
        .displayName("Nap")
        .description("Opens the nap screen, or naps straight away.")
    }
}

/// "Wind-down": start now within its window, or cancel if running, without opening the app;
/// shows its state. Or opens the app first.
struct WindDownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.bedtimebridge.control.winddown", provider: WindDownControlProvider()) { value in
            ControlWidgetToggle("Wind-down", isOn: value.running, action: WindDownControlIntent()) { on in
                Label(on ? "Winding down" : (value.canStart ? "Start" : "Not yet"), systemImage: on ? "moon.zzz.fill" : "moon.zzz")
            }
        }
        .displayName("Wind-down")
        .description("Starts tonight's wind-down now, or cancels it.")
    }
}

struct WindDownControlValue {
    var running: Bool
    var canStart: Bool
}

struct WindDownControlProvider: ControlValueProvider {
    var previewValue: WindDownControlValue { WindDownControlValue(running: false, canStart: true) }
    func currentValue() async throws -> WindDownControlValue {
        let snapshot = NextAlarmSnapshot.load()
        return WindDownControlValue(running: snapshot.windDownStatus == "winding_down", canStart: snapshot.windDownCanStart ?? false)
    }
}

/// "Tonight": opens tonight's plan and alarm status.
struct TonightControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.bedtimebridge.control.tonight") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "bedtimebridge://tonight")!)) { Label("Tonight", systemImage: "alarm") }
        }
        .displayName("Tonight")
        .description("Opens tonight's plan and alarm status.")
    }
}
