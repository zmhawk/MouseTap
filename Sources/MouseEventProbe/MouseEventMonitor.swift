import AppKit
import CoreGraphics
import Foundation

final class MouseEventMonitor: @unchecked Sendable {
    var onInputDetected: ((MouseInput) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    private let stateLock = NSLock()
    private var bindings: [String: ShortcutBinding] = [:]
    private var learningMode = false
    private var swallowedButtons = Set<String>()
    private var shortcutCaptureActive = false
    private var shortcutCaptureCallback: ((ShortcutBinding?) -> Void)?
    private var swallowedShortcutKeyUps = Set<UInt16>()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        guard tap == nil else { return }

        let eventTypes: [CGEventType] = [
            .otherMouseDown, .otherMouseUp, .scrollWheel, .keyDown, .keyUp,
        ]
        let eventMask = eventTypes.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: mouseEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            reportStatus("无法创建监听器；请检查 macOS 的输入监控/辅助功能权限")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            reportStatus("无法创建事件监听循环")
            return
        }

        tap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        reportStatus("正在监听鼠标中键、额外按键和横向拨轮")
    }

    func stop() {
        stateLock.lock()
        let captureCallback = shortcutCaptureCallback
        shortcutCaptureCallback = nil
        shortcutCaptureActive = false
        stateLock.unlock()

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil

        if let captureCallback {
            DispatchQueue.main.async { captureCallback(nil) }
        }
    }

    func setBindings(_ bindings: [String: ShortcutBinding]) {
        stateLock.lock()
        self.bindings = bindings
        stateLock.unlock()
    }

    func setLearningMode(_ enabled: Bool) {
        stateLock.lock()
        learningMode = enabled
        stateLock.unlock()
    }

    func beginShortcutCapture(_ completion: @escaping (ShortcutBinding?) -> Void) {
        guard CGPreflightListenEventAccess() else {
            _ = CGRequestListenEventAccess()
            reportStatus("请允许输入监控权限，然后再次点击录制快捷键")
            completion(nil)
            return
        }

        // Recreate the tap after permission changes so its keyboard event mask is refreshed.
        stop()
        start()

        stateLock.lock()
        shortcutCaptureCallback = completion
        shortcutCaptureActive = true
        stateLock.unlock()
    }

    func cancelShortcutCapture() {
        stateLock.lock()
        let callback = shortcutCaptureCallback
        shortcutCaptureCallback = nil
        shortcutCaptureActive = false
        stateLock.unlock()

        DispatchQueue.main.async {
            callback?(nil)
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyUp {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            stateLock.lock()
            let wasCaptured = swallowedShortcutKeyUps.remove(keyCode) != nil
            stateLock.unlock()
            return wasCaptured ? nil : Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            return handleShortcutKeyDown(event)
        }

        if type == .otherMouseUp {
            guard let input = MouseInput.button(event.getIntegerValueField(.mouseEventButtonNumber)) else {
                return Unmanaged.passUnretained(event)
            }

            stateLock.lock()
            let wasSwallowed = swallowedButtons.remove(input.id) != nil
            stateLock.unlock()
            return wasSwallowed ? nil : Unmanaged.passUnretained(event)
        }

        if type == .otherMouseDown {
            guard let input = MouseInput.button(event.getIntegerValueField(.mouseEventButtonNumber)) else {
                return Unmanaged.passUnretained(event)
            }
            return handleActivation(input, event: event)
        }

        if type == .scrollWheel {
            let lineDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let pixelDelta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let delta = lineDelta != 0 ? lineDelta : pixelDelta
            guard let input = MouseInput.horizontalScroll(delta) else {
                return Unmanaged.passUnretained(event)
            }
            return handleActivation(input, event: event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleActivation(_ input: MouseInput, event: CGEvent) -> Unmanaged<CGEvent>? {
        stateLock.lock()
        let learning = learningMode || shortcutCaptureActive
        let shortcut = bindings[input.id]
        if !learning, shortcut != nil, input.id.hasPrefix("button.") {
            swallowedButtons.insert(input.id)
        }
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.onInputDetected?(input)
        }

        guard !learning, let shortcut else { return Unmanaged.passUnretained(event) }
        DispatchQueue.main.async {
            shortcut.post()
        }
        return nil
    }

    private func handleShortcutKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        stateLock.lock()
        guard shortcutCaptureActive else {
            stateLock.unlock()
            return Unmanaged.passUnretained(event)
        }

        swallowedShortcutKeyUps.insert(keyCode)
        let callback = shortcutCaptureCallback
        shortcutCaptureCallback = nil
        shortcutCaptureActive = false
        stateLock.unlock()

        if keyCode == 53 {
            DispatchQueue.main.async { callback?(nil) }
            return nil
        }

        guard let nativeEvent = NSEvent(cgEvent: event) else {
            DispatchQueue.main.async { callback?(nil) }
            return nil
        }
        let shortcut = ShortcutBinding(event: nativeEvent)
        DispatchQueue.main.async { callback?(shortcut) }
        return nil
    }

    private func reportStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChanged?(message)
        }
    }
}

private func mouseEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<MouseEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
