import SwiftUI
import UIKit

@main
struct BedtimeBridgeApp: App {
    init() {
        // Navigation titles (e.g. Settings) in Sora to match the Tonight screen.
        let appearance = UINavigationBar.appearance()
        if let large = UIFont(name: "Sora-SemiBold", size: 34), let inline = UIFont(name: "Sora-SemiBold", size: 17) {
            appearance.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
            appearance.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)]
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(SettingsStore.shared)
                // Nightfall is a dark-only theme: a bedside app shouldn't flash white.
                .preferredColorScheme(.dark)
                .tint(Theme.accentIcon)
        }
    }
}
