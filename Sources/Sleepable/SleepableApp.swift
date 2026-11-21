import AppKit
import SwiftUI

@main
struct SleepableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(state)
        } label: {
            Image(systemName: state.menuBarSymbol)
                .accessibilityLabel("Sleepable")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            AppState.shared.start()
            if !AppState.shared.hasCompletedSetup {
                SetupWindowController.shared.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Re-launching the app from Finder/Launchpad opens the setup page.
        Task { @MainActor in SetupWindowController.shared.show() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.shutdown() }
    }
}

/// Hosts the setup / landing page in a regular window, even though Sleepable
/// lives in the menu bar and has no Dock icon.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    static let shared = SetupWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SetupView().environmentObject(AppState.shared))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Sleepable"
            win.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isMovableByWindowBackground = true
            win.setContentSize(NSSize(width: 640, height: 760))
            win.center()
            win.isReleasedWhenClosed = false
            win.delegate = self
            window = win
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        // Go back to being a pure menu bar app.
        NSApp.setActivationPolicy(.accessory)
    }
}
