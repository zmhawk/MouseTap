import Foundation
import XCTest
@testable import MouseTap

final class PreferencesMigrationTests: XCTestCase {
    func testMigrationPreservesExistingValuesAndOnlyRunsOnce() throws {
        let name = "MouseTap.MigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "mousetap.scroll.reverse-vertical")
        let bindings = Data("saved bindings".utf8)
        PreferencesMigration.run(to: defaults, legacy: [
            "mouse-kit.bindings.v1": bindings,
            "mouse-kit.scroll.reverse-vertical": true,
            "mouse-kit.scroll.reverse-horizontal": true,
            "unrelated-setting": "ignored",
        ])
        XCTAssertEqual(defaults.data(forKey: "mousetap.bindings.v1"), bindings)
        XCTAssertFalse(defaults.bool(forKey: "mousetap.scroll.reverse-vertical"))
        XCTAssertTrue(defaults.bool(forKey: "mousetap.scroll.reverse-horizontal"))
        XCTAssertNil(defaults.object(forKey: "unrelated-setting"))
        defaults.removeObject(forKey: "mousetap.bindings.v1")
        PreferencesMigration.run(to: defaults, legacy: ["mouse-kit.bindings.v1": bindings])
        XCTAssertNil(defaults.object(forKey: "mousetap.bindings.v1"))
    }
}
