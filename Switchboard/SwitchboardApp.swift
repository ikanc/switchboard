import SwiftUI

@main
struct SwitchboardApp: App {
    @StateObject private var manager = ServiceManager()

    var body: some Scene {
        MenuBarExtra {
            ServiceListView(manager: manager)
                .frame(width: 400, height: 560)
        } label: {
            let icon = manager.allRunning ? "bolt.fill"
                : manager.anyRunning ? "bolt.badge.clock.fill"
                : "bolt.slash.fill"
            Image(systemName: icon)
        }
        .menuBarExtraStyle(.window)

        // Full window for in-depth control. Shares the same ServiceManager, so
        // the dropdown and window stay in sync. The app is an LSUIElement
        // accessory, so closing this window leaves every service running.
        Window("Switchboard", id: "dashboard") {
            MainWindowView(manager: manager)
        }
        .defaultSize(width: 920, height: 620)
    }
}
