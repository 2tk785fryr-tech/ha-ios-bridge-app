import UIKit

/// The battery level and whether it's charging, sent with bedtime (v0.4.3 item 10).
enum PhoneBattery {
    @MainActor
    static func reading() -> [String: Any] {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        guard device.batteryLevel >= 0 else { return [:] }
        return [
            "battery_level": Int((device.batteryLevel * 100).rounded()),
            "battery_charging": device.batteryState == .charging || device.batteryState == .full,
        ]
    }
}
