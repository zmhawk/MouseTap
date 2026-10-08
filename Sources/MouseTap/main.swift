import AppKit
import CoreServices
import SwiftUI

@main
@MainActor
struct MouseTapApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = MouseTapAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

extension Notification.Name {
    static let mouseTapWindowHidden = Notification.Name("MouseTapWindowHidden")
}

@MainActor
final class MouseTapAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PreferencesMigration.run()
        NSApp.setActivationPolicy(.accessory)
        // Listening belongs to the application, even when no window exists.
        MouseEventMonitor.shared.setBindings(BindingStore.load())
        MouseEventMonitor.shared.start()

        if ProcessInfo.processInfo.arguments.contains("--enable-login") {
            LaunchAtLogin.shared.setEnabled(true)
        }
        let launchReason = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        let background = launchReason == OSType(keyAELaunchedAsLogInItem)
            || ProcessInfo.processInfo.arguments.contains("--background")
        if !background { showMainWindow() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NotificationCenter.default.post(name: .mouseTapWindowHidden, object: sender)
        sender.orderOut(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MouseEventMonitor.shared.stop()
    }

    private func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MouseTap"
            window.contentView = NSHostingView(rootView: ContentView())
            window.minSize = NSSize(width: 600, height: 660)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("MouseTapSettings")
            mainWindow = window
        }
        guard let mainWindow else { return }
        if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
    }
}
