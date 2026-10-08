import AppKit
import CoreGraphics

struct MouseInput: Codable, Hashable, Identifiable, Sendable {
    let id: String

    var title: String {
        if id.hasPrefix("button."), let number = Int(id.dropFirst("button.".count)) {
            return number == 2 ? "中键" : "鼠标按钮 \(number)"
        }

        switch id {
        case "scroll.left": return "横向拨轮 ←"
        case "scroll.right": return "横向拨轮 →"
        default: return id
        }
    }

    static func button(_ number: Int64) -> MouseInput? {
        guard number >= 2 else { return nil }
        return MouseInput(id: "button.\(number)")
    }

    static func horizontalScroll(_ delta: Int64) -> MouseInput? {
        guard delta != 0 else { return nil }
        return MouseInput(id: delta < 0 ? "scroll.left" : "scroll.right")
    }
}

struct ShortcutBinding: Codable, Hashable, Sendable {
    let keyCode: UInt16
    let command: Bool
    let option: Bool
    let control: Bool
    let shift: Bool
    let keyName: String

    init(event: NSEvent) {
        keyCode = event.keyCode
        command = event.modifierFlags.contains(.command)
        option = event.modifierFlags.contains(.option)
        control = event.modifierFlags.contains(.control)
        shift = event.modifierFlags.contains(.shift)
        keyName = Self.name(for: event)
    }

    var displayName: String {
        var parts = ""
        if control { parts += "⌃" }
        if option { parts += "⌥" }
        if shift { parts += "⇧" }
        if command { parts += "⌘" }
        return parts + keyName
    }

    func post() {
        var flags: CGEventFlags = []
        if control { flags.insert(.maskControl) }
        if option { flags.insert(.maskAlternate) }
        if shift { flags.insert(.maskShift) }
        if command { flags.insert(.maskCommand) }

        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)
        else { return }

        keyDown.flags = flags
        keyUp.flags = flags
        // Inject at the HID entry point so WindowServer and system-wide
        // shortcut handlers see the chord before it is routed to an app.
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func name(for event: NSEvent) -> String {
        let specialKeys: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
            115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        if let special = specialKeys[event.keyCode] { return special }

        let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return characters.isEmpty ? "Key \(event.keyCode)" : characters.uppercased()
    }
}
