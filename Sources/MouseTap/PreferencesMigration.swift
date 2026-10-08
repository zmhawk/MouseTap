import Foundation

/// Changing the bundle ID creates a new preferences domain. Import only our
/// saved settings once, preserving any values already set in MouseTap.
enum PreferencesMigration {
    private static let marker = "mousetap.migrated-mousekit.v1"
    private static let keys = [
        "mouse-kit.bindings.v1": "mousetap.bindings.v1",
        "mouse-kit.scroll.reverse-vertical": "mousetap.scroll.reverse-vertical",
        "mouse-kit.scroll.reverse-horizontal": "mousetap.scroll.reverse-horizontal",
        "NSWindow Frame MouseKitSettings": "NSWindow Frame MouseTapSettings",
    ]

    static func run(to defaults: UserDefaults = .standard, legacy: [String: Any]? = nil) {
        guard !defaults.bool(forKey: marker) else { return }
        let previous = legacy ?? defaults.persistentDomain(forName: "com.yujianbo.mousekit") ?? [:]
        for (old, new) in keys where defaults.object(forKey: new) == nil {
            if let value = previous[old] { defaults.set(value, forKey: new) }
        }
        defaults.set(true, forKey: marker)
    }
}
