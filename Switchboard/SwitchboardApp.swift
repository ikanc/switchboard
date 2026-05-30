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
    }
}
