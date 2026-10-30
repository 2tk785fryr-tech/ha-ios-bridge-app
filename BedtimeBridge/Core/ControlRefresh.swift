import WidgetKit

/// Asks the system to redraw the controls and the widget after their state changed.
enum ControlRefresh {
    static func reload() {
        ControlCenter.shared.reloadAllControls()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
