import AppKit
import CoreGraphics
import Foundation
import os

final class MouseEventMonitor: @unchecked Sendable {
    static let shared = MouseEventMonitor()
    private let logger = Logger(subsystem: "com.zmhawk.mousetap", category: "EventMonitor")

    var onInputDetected: ((MouseInput) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    private let shortcutQueue = DispatchQueue(label: "com.zmhawk.mousetap.shortcuts", qos: .userInteractive)
    private lazy var wheelShortcuts = WheelShortcutScheduler(queue: shortcutQueue) { [weak self] request in
        guard let self else { return }
        self.stateLock.lock()
        let valid = self.serviceActive && !self.learningMode && !self.shortcutCaptureActive
            && self.bindings[request.inputID] == request.shortcut
        self.stateLock.unlock()
        if valid { self.postShortcut(request.shortcut) }
    }
    private let stateLock = NSLock()
    private var bindings: [String: ShortcutBinding] = [:]
    private var scrollSettings = ScrollSettings.load()
    private var learningMode = false
    private var swallowedButtons = Set<String>()
    private var shortcutCaptureActive = false
    private var shortcutCaptureCallback: ((ShortcutBinding?) -> Void)?
    private var swallowedShortcutKeyUps = Set<UInt16>()
    private var tap: CFMachPort?
    private var eventRunLoop: EventTapRunLoop?
    private var serviceActive = false
    private var postAccessReady = false
    private var inputNotificationPending = false
    private var latestDetectedInput: MouseInput?

    private init() {
        // Initialize once before callbacks and the main thread can access it.
        _ = wheelShortcuts
    }

    func start(captureKeyboard: Bool = false) {
        guard tap == nil else {
            stateLock.lock()
            let active = serviceActive
            stateLock.unlock()
            if !active {
                reportStatus("鼠标服务已暂停；请退出并重新打开 MouseTap")
            } else if !postEventAccessIsReadyForBindings() {
                reportStatus("正在监听；请允许 MouseTap 合成键盘事件，绑定才能触发")
            } else {
                reportStatus("正在监听鼠标中键、额外按键和横向拨轮")
            }
            return
        }

        guard CGPreflightListenEventAccess() else {
            _ = CGRequestListenEventAccess()
            reportStatus("请在系统设置的“输入监控”中允许 MouseTap，然后重新打开窗口")
            return
        }

        let canSynthesizeForBindings = postEventAccessIsReadyForBindings()

        var eventTypes: [CGEventType] = [.otherMouseDown, .otherMouseUp, .scrollWheel]
        if captureKeyboard { eventTypes += [.keyDown, .keyUp] }
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

        stateLock.lock()
        tap = eventTap
        serviceActive = true
        postAccessReady = canSynthesizeForBindings
        stateLock.unlock()
        eventRunLoop = EventTapRunLoop(source: source)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        reportStatus(
            canSynthesizeForBindings
                ? "正在监听鼠标中键、额外按键和横向拨轮"
                : "正在监听；请允许 MouseTap 合成键盘事件，绑定才能触发"
        )
    }

    func stop() {
        wheelShortcuts.cancel()
        stateLock.lock()
        let captureCallback = shortcutCaptureCallback
        shortcutCaptureCallback = nil
        shortcutCaptureActive = false
        stateLock.unlock()

        stateLock.lock()
        serviceActive = false
        let oldTap = tap
        tap = nil
        swallowedButtons.removeAll()
        swallowedShortcutKeyUps.removeAll()
        stateLock.unlock()
        if let oldTap {
            CGEvent.tapEnable(tap: oldTap, enable: false)
            CFMachPortInvalidate(oldTap)
        }
        eventRunLoop?.stop()
        eventRunLoop = nil

        if let captureCallback {
            DispatchQueue.main.async { captureCallback(nil) }
        }
    }

    func setBindings(_ bindings: [String: ShortcutBinding]) {
        let allowed = CGPreflightPostEventAccess()
        wheelShortcuts.cancel()
        stateLock.lock()
        self.bindings = bindings
        postAccessReady = allowed
        stateLock.unlock()
    }

    func setScrollSettings(_ settings: ScrollSettings) {
        stateLock.lock()
        scrollSettings = settings
        stateLock.unlock()
    }

    func setLearningMode(_ enabled: Bool) {
        if enabled { wheelShortcuts.cancel() }
        stateLock.lock()
        learningMode = enabled
        stateLock.unlock()
    }

    func beginShortcutCapture(_ completion: @escaping (ShortcutBinding?) -> Void) {
        guard CGPreflightListenEventAccess() else {
            _ = CGRequestListenEventAccess()
            reportStatus("请在系统设置的“输入监控”中允许 MouseTap，然后再次录制快捷键")
            completion(nil)
            return
        }

        guard CGPreflightPostEventAccess() else {
            _ = CGRequestPostEventAccess()
            reportStatus("请在系统设置中允许 MouseTap 合成键盘事件，然后再次录制快捷键")
            completion(nil)
            return
        }

        // Recreate the tap after permission changes so its keyboard event mask is refreshed.
        stop()
        start(captureKeyboard: true)

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
            logger.error("Event tap interrupted (type \(type.rawValue)); service paused to protect system input")
            // Leave the tap disabled: automatic retry can repeatedly stall input.
            stateLock.lock()
            serviceActive = false
            swallowedButtons.removeAll()
            swallowedShortcutKeyUps.removeAll()
            stateLock.unlock()
            wheelShortcuts.cancel()
            reportStatus("鼠标服务已因监听中断暂停；系统输入已放行，请重新打开应用")
            return Unmanaged.passUnretained(event)
        }

        stateLock.lock()
        let active = serviceActive
        stateLock.unlock()
        guard active else { return Unmanaged.passUnretained(event) }

        // Synthetic events must pass through even if recording starts while
        // a queued shortcut is finishing. Seeing them here only confirms delivery
        // to this tap, not that the foreground app performed an action.
        if event.getIntegerValueField(.eventSourceUserData) == ShortcutBinding.generatedEventUserData {
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

        if type == .flagsChanged {
            return Unmanaged.passUnretained(event)
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
            guard ScrollSettings.isMouseWheelEvent(event) else {
                return Unmanaged.passUnretained(event)
            }
            let lineDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let pixelDelta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let delta = lineDelta != 0 ? lineDelta : pixelDelta
            // Resolve physical input bindings before reversing ordinary scroll.
            // A bound wheel keeps its shortcut and never leaks a scroll event.
            if let input = MouseInput.horizontalScroll(delta),
               handleActivation(input, event: event) == nil {
                return nil
            }
            stateLock.lock()
            let settings = scrollSettings
            stateLock.unlock()
            settings.apply(to: event)
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleActivation(_ input: MouseInput, event: CGEvent) -> Unmanaged<CGEvent>? {
        stateLock.lock()
        let learning = learningMode || shortcutCaptureActive
        let shortcut = bindings[input.id]
        let canPostShortcut = postAccessReady
        stateLock.unlock()

        // Permission checks may involve system IPC; never do them in a tap callback.
        // The cached value gates swallowing; the worker rechecks before posting.

        if !learning, shortcut != nil, canPostShortcut, input.id.hasPrefix("button.") {
            stateLock.lock()
            swallowedButtons.insert(input.id)
            stateLock.unlock()
        }

        notifyInput(input)

        guard !learning, let shortcut, canPostShortcut else {
            return Unmanaged.passUnretained(event)
        }
        // Repeated button presses must be bounded too, not just wheel events.
        wheelShortcuts.submit(inputID: input.id, shortcut: shortcut)
        return nil
    }

    private func postShortcut(_ shortcut: ShortcutBinding) {
        let didPost = shortcut.post()
        reportStatus(
            didPost
                ? "已提交快捷键：\(shortcut.displayName)"
                : "快捷键未发送；请检查 MouseTap 的按键合成权限"
        )
    }

    private func handleShortcutKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        stateLock.lock()
        if swallowedShortcutKeyUps.contains(keyCode) {
            stateLock.unlock()
            return nil
        }
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

    private func notifyInput(_ input: MouseInput) {
        stateLock.lock()
        latestDetectedInput = input
        let shouldSchedule = !inputNotificationPending
        inputNotificationPending = true
        stateLock.unlock()
        guard shouldSchedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let latest = self.latestDetectedInput
            self.latestDetectedInput = nil
            self.inputNotificationPending = false
            self.stateLock.unlock()
            if let latest { self.onInputDetected?(latest) }
        }
    }

    private func reportStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChanged?(message)
        }
    }

    private func postEventAccessIsReadyForBindings() -> Bool {
        stateLock.lock()
        let hasBindings = !bindings.isEmpty
        stateLock.unlock()

        guard hasBindings else { return true }
        let allowed = CGPreflightPostEventAccess()
        stateLock.lock()
        postAccessReady = allowed
        stateLock.unlock()
        if !allowed { _ = CGRequestPostEventAccess() }
        return allowed
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
