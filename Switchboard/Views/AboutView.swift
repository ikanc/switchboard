import AppKit
import SwiftUI

// Custom About window. We don't use NSApplication.orderFrontStandardAboutPanel
// because the standard panel renders the credit line as a system link we can't
// intercept — and we want clicking it to open the project page *and* dismiss
// the window.
struct AboutView: View {
    let onClose: () -> Void

    private let projectURL = URL(string: "https://www.codejitsu.ca/switchboard/")!

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
                .padding(.top, 6)

            Text("Switchboard")
                .font(.title2.weight(.semibold))

            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Start, stop, and watch your local dev services from the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Text("Open source — contributions welcome.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.open(projectURL)
                onClose()
            } label: {
                Text("Developed by Ika @ Codejitsu.ca")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
            .help("Open codejitsu.ca/switchboard")
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 320)
    }
}

// Owns the single About window instance so it survives across opens and can be
// closed programmatically (e.g. when the credit link is clicked).
@MainActor
final class AboutPanelPresenter {
    static let shared = AboutPanelPresenter()

    private var window: NSWindow?

    func show() {
        // Snapshot what's visible right now — the MenuBarExtra panel that
        // launched this action. We hide it below so About replaces the dropdown
        // instead of stacking on top of it.
        let menuBarPanels = NSApp.windows.filter { $0.isVisible }

        let window: NSWindow
        if let existing = self.window {
            window = existing
        } else {
            let hosting = NSHostingController(rootView: AboutView(onClose: { [weak self] in
                self?.window?.close()
            }))
            window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "About Switchboard"
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.setContentSize(hosting.view.fittingSize)
            window.center()
            self.window = window
        }

        for panel in menuBarPanels where panel !== window {
            panel.orderOut(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
