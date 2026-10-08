import CoreGraphics
import Foundation

struct ScrollSettings: Codable, Equatable, Sendable {
    var reverseVertical = false
    var reverseHorizontal = false

    static func load(from defaults: UserDefaults = .standard) -> ScrollSettings {
        ScrollSettings(
            reverseVertical: defaults.bool(forKey: "mousetap.scroll.reverse-vertical"),
            reverseHorizontal: defaults.bool(forKey: "mousetap.scroll.reverse-horizontal")
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(reverseVertical, forKey: "mousetap.scroll.reverse-vertical")
        defaults.set(reverseHorizontal, forKey: "mousetap.scroll.reverse-horizontal")
    }

    static func isMouseWheelEvent(_ event: CGEvent) -> Bool {
        // Phased gestures and their momentum belong to the trackpad. Unphased
        // mouse wheels can be line-based or pixel-based, so handle both units.
        event.type == .scrollWheel
            && event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0
            && event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0
    }

    func apply(to event: CGEvent) {
        guard Self.isMouseWheelEvent(event), reverseVertical || reverseHorizontal else { return }

        var fields: [CGEventField] = []
        if reverseVertical {
            fields += [.scrollWheelEventDeltaAxis1,
                       .scrollWheelEventFixedPtDeltaAxis1,
                       .scrollWheelEventPointDeltaAxis1]
        }
        if reverseHorizontal {
            fields += [.scrollWheelEventDeltaAxis2,
                       .scrollWheelEventFixedPtDeltaAxis2,
                       .scrollWheelEventPointDeltaAxis2]
        }
        // Read all representations before changing any, preserving fractions
        // and acceleration rather than rebuilding or reposting the event.
        let values = fields.map { event.getIntegerValueField($0) }
        for (field, value) in zip(fields, values) {
            event.setIntegerValueField(field, value: value == Int64.min ? Int64.max : -value)
        }
    }
}
