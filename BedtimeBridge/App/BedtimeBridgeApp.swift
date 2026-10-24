import SwiftUI

@main
struct BedtimeBridgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(SettingsStore.shared)
        }
    }
}
