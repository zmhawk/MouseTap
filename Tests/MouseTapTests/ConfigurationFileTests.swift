import Foundation
import XCTest
@testable import MouseTap

final class ConfigurationFileTests: XCTestCase {
    private var exampleURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Examples/mousetap.toml")
    }

    func testExampleAndRoundTrip() throws {
        let original = try ConfigurationFile.read(from: exampleURL)
        XCTAssertEqual(original.bindings["button.3"]?.displayName, "Fn+⇧A")
        XCTAssertEqual(original.bindings["button.2"]?.displayName, "⌃↑")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try original.write(to: url)
        XCTAssertEqual(try ConfigurationFile.read(from: url), original)
    }

    func testInvalidInputsAndVersionAreRejected() throws {
        let original = try String(contentsOf: exampleURL, encoding: .utf8)
        for invalid in [original.replacingOccurrences(of: "version = 1", with: "version = 2"),
                        original.replacingOccurrences(of: "button.2", with: "button.1"),
                        original.replacingOccurrences(of: "button.2", with: "button.02"),
                        original.replacingOccurrences(of: "scroll.left", with: "scroll.up"),
                        original.replacingOccurrences(of: "keyCode = 126", with: "keyCode = 900"),
                        original.replacingOccurrences(of: "control = true", with: "control = \"true\""),
                        original.replacingOccurrences(of: "function", with: "functoin"),
                        original.replacingOccurrences(of: "reverseVertical", with: "reverseVertcial"),
                        original.replacingOccurrences(of: "keyCode = 126", with: "keyCode = 126\nkeyCode = 124"),
                        original.replacingOccurrences(of: "[bindings.\"button.2\"]", with: "[bindings.button.2]"),
                        "{broken"] {
            XCTAssertThrowsError(try ConfigurationFile.decode(Data(invalid.utf8)))
        }
    }

    func testHandEditsCommentsAndEmptyBindings() throws {
        let text = """
        # Manual edits are allowed.
        version = 1
        [scroll]
        reverseVertical = true # reverse the vertical wheel
        reverseHorizontal = false
        [bindings]
        """
        let result = try ConfigurationFile.decode(Data(text.utf8))
        XCTAssertTrue(result.bindings.isEmpty)
        XCTAssertTrue(result.scroll.reverseVertical)
        XCTAssertFalse(result.scroll.reverseHorizontal)
    }

    func testMalformedConfigurationDoesNotChangePreferences() throws {
        let before = UserDefaults.standard.dictionaryRepresentation()
        XCTAssertThrowsError(try ConfigurationFile.decode(Data("[bindings]".utf8)))
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
    }

    func testOversizedFilesAndInvalidEncodingAreRejected() {
        XCTAssertThrowsError(try ConfigurationFile.decode(Data(repeating: 32, count: ConfigurationFile.maximumFileSize + 1)))
        XCTAssertThrowsError(try ConfigurationFile.decode(Data([0xFF, 0xFE])))
    }
}
