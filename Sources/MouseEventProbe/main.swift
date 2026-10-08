import AppKit
import SwiftUI

@main
struct MouseKitApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Mouse Kit") {
            ContentView()
                .frame(minWidth: 560, minHeight: 440)
        }
    }
}
