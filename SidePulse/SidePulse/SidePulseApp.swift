import AppIntents
import SwiftUI

@main
struct SidePulseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if #available(iOS 17.0, *) {
            SidePulseShortcuts.updateAppShortcutParameters()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
