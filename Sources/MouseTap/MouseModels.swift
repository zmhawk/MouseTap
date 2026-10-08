import AppKit
import CoreGraphics
import IOKit.hidsystem

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
    static let generatedEventUserData: Int64 = 0x4D4F555345544150

    let keyCode: UInt16
    let command: Bool
    let option: Bool
    let control: Bool
    let shift: Bool
    let function: Bool
    let keyName: String

    init(event: NSEvent) {
        keyCode = event.keyCode
        command = event.modifierFlags.contains(.command)
        option = event.modifierFlags.contains(.option)
        control = event.modifierFlags.contains(.control)
        shift = event.modifierFlags.contains(.shift)
        // Arrows carry the function flag even when Fn is not held. In that
        // case only record an explicit Fn press from the physical key state.
        function = event.modifierFlags.contains(.function)
            && (Self.keyIdentityFlags(for: event.keyCode).isEmpty
                || CGEventSource.keyState(.hidSystemState, key: 63))
        keyName = Self.name(for: event)
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, command, option, control, shift, function, keyName
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try values.decode(UInt16.self, forKey: .keyCode)
        command = try values.decode(Bool.self, forKey: .command)
        option = try values.decode(Bool.self, forKey: .option)
        control = try values.decode(Bool.self, forKey: .control)
        shift = try values.decode(Bool.self, forKey: .shift)
        function = try values.decodeIfPresent(Bool.self, forKey: .function) ?? false
        keyName = try values.decode(String.self, forKey: .keyName)
    }

    var displayName: String {
        var parts = function ? "Fn+" : ""
        if control { parts += "⌃" }
        if option { parts += "⌥" }
        if shift { parts += "⇧" }
        if command { parts += "⌘" }
        return parts + keyName
    }

    @discardableResult
    func post() -> Bool {
        guard CGPreflightPostEventAccess() else {
            return false
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

        let modifiers: [(keyCode: UInt16, flag: CGEventFlags, deviceFlag: CGEventFlags)] = [
            (63, .maskSecondaryFn, []),
            (59, .maskControl, CGEventFlags(rawValue: UInt64(NX_DEVICELCTLKEYMASK))),
            (58, .maskAlternate, CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))),
            (56, .maskShift, CGEventFlags(rawValue: UInt64(NX_DEVICELSHIFTKEYMASK))),
            (55, .maskCommand, CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK))),
        ].filter { modifier in
            switch modifier.flag {
            case .maskSecondaryFn: return function
            case .maskControl: return control
            case .maskAlternate: return option
            case .maskShift: return shift
            case .maskCommand: return command
            default: return false
            }
        }

        var flags: CGEventFlags = []
        var modifierDownEvents: [CGEvent] = []
        for modifier in modifiers {
            flags.formUnion([modifier.flag, modifier.deviceFlag])
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(modifier.keyCode),
                keyDown: true
            ) else { return false }
            event.type = .flagsChanged
            event.flags = flags
            modifierDownEvents.append(event)
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false)
        else { return false }
        // Arrow keys carry these flags on physical keyboards. System shortcut
        // handlers need the key identity flags as well as the modifier chord.
        let keyFlags = Self.keyIdentityFlags(for: keyCode)
        keyDown.flags = flags.union(keyFlags)
        keyUp.flags = flags.union(keyFlags)

        var modifierUpEvents: [CGEvent] = []
        for modifier in modifiers.reversed() {
            flags.subtract([modifier.flag, modifier.deviceFlag])
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(modifier.keyCode),
                keyDown: false
            ) else { return false }
            event.type = .flagsChanged
            event.flags = flags
            modifierUpEvents.append(event)
        }

        // Keep modifier and key state alive long enough for system shortcut
        // handlers to process each transition. The caller uses a serial worker
        // queue so these delays neither block the event tap nor interleave chords.
        func send(_ event: CGEvent) {
            event.timestamp = CGEventTimestamp(DispatchTime.now().uptimeNanoseconds)
            event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(source.keyboardType))
            event.setIntegerValueField(.eventSourceUserData, value: Self.generatedEventUserData)
            event.post(tap: .cghidEventTap)
        }
        for event in modifierDownEvents {
            send(event)
            Thread.sleep(forTimeInterval: 0.015)
        }
        send(keyDown)
        Thread.sleep(forTimeInterval: 0.05)
        send(keyUp)
        Thread.sleep(forTimeInterval: 0.015)
        for event in modifierUpEvents {
            send(event)
            Thread.sleep(forTimeInterval: 0.015)
        }
        return true
    }

    static func keyIdentityFlags(for keyCode: UInt16) -> CGEventFlags {
        switch keyCode {
        case 123...126: return [.maskSecondaryFn, .maskNumericPad]
        default: return []
        }
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


enum BindingStore {
    private static let key = "mousetap.bindings.v1"

    static func load() -> [String: ShortcutBinding] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: ShortcutBinding].self, from: data)) ?? [:]
    }

    static func save(_ bindings: [String: ShortcutBinding]) {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
