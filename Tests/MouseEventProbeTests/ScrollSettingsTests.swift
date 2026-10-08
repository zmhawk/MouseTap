import CoreGraphics
import Foundation
import XCTest
@testable import MouseEventProbe

final class ScrollSettingsTests: XCTestCase {
    private let vertical: [CGEventField] = [
        .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1,
    ]
    private let horizontal: [CGEventField] = [
        .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2,
    ]

    private func event(pixelBased: Bool = false) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: pixelBased ? .pixel : .line,
                            wheelCount: 2, wheel1: 3, wheel2: -2, wheel3: 0)!
        // Different units, including fractional lines, must all be retained.
        for (field, value) in zip(vertical + horizontal, [3, 98304, 27, -2, -32768, -11] as [Int64]) {
            event.setIntegerValueField(field, value: value)
        }
        return event
    }

    func testAxesReverseIndependentlyInBothUnits() {
        for pixels in [false, true] {
            for settings in [ScrollSettings(), ScrollSettings(reverseVertical: true),
                             ScrollSettings(reverseHorizontal: true),
                             ScrollSettings(reverseVertical: true, reverseHorizontal: true)] {
                let event = event(pixelBased: pixels)
                let before = (vertical + horizontal).map { event.getIntegerValueField($0) }
                let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
                settings.apply(to: event)
                for (index, field) in (vertical + horizontal).enumerated() {
                    let reversed = index < 3 ? settings.reverseVertical : settings.reverseHorizontal
                    XCTAssertEqual(event.getIntegerValueField(field), before[index] * (reversed ? -1 : 1))
                }
                XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous), continuous)
                // The same event is edited; replaying it is unnecessary.
                settings.apply(to: event)
                XCTAssertEqual((vertical + horizontal).map { event.getIntegerValueField($0) }, before)
            }
        }
    }

    func testTrackpadPhasesAndMomentumAreUntouched() {
        for phaseField: CGEventField in [.scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase] {
            let phases: [Int64] = phaseField == .scrollWheelEventScrollPhase
                ? [1, 2, 4, 8, 128] : [1, 2, 4]
            for phase in phases {
                let event = event(pixelBased: true)
                event.setIntegerValueField(phaseField, value: phase)
                let before = (vertical + horizontal).map { event.getIntegerValueField($0) }
                ScrollSettings(reverseVertical: true, reverseHorizontal: true).apply(to: event)
                XCTAssertEqual((vertical + horizontal).map { event.getIntegerValueField($0) }, before)
                XCTAssertEqual(event.getIntegerValueField(phaseField), phase)
            }
        }
    }

    func testZeroDeltasAndNonScrollEventsAreUntouched() {
        let zero = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                           wheel1: 0, wheel2: 0, wheel3: 0)!
        let settings = ScrollSettings(reverseVertical: true, reverseHorizontal: true)
        settings.apply(to: zero)
        for field in vertical + horizontal { XCTAssertEqual(zero.getIntegerValueField(field), 0) }
        let key = CGEvent(keyboardEventSource: nil, virtualKey: 126, keyDown: true)!
        let flags = key.flags
        settings.apply(to: key)
        XCTAssertEqual(key.type, .keyDown)
        XCTAssertEqual(key.flags, flags)
        XCTAssertEqual(key.getIntegerValueField(.keyboardEventKeycode), 126)
    }

    func testDefaultsAndPersistence() {
        let suite = "MouseKit.ScrollTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ScrollSettings.load(from: defaults), ScrollSettings())
        let settings = ScrollSettings(reverseVertical: true, reverseHorizontal: false)
        settings.save(to: defaults)
        XCTAssertEqual(ScrollSettings.load(from: defaults), settings)
        ScrollSettings().save(to: defaults)
        XCTAssertEqual(ScrollSettings.load(from: defaults), ScrollSettings())
    }
}
