import Dispatch
import Foundation

struct WheelShortcutRequest: Sendable {
    let inputID: String
    let shortcut: ShortcutBinding
    let receivedAt: TimeInterval
}

struct WheelShortcutBuffer {
    enum Action {
        case idle
        case wait(TimeInterval)
        case send(WheelShortcutRequest)
    }

    let minimumInterval: TimeInterval
    let maximumAge: TimeInterval
    private(set) var pending: WheelShortcutRequest?
    private var nextAllowedAt: TimeInterval = 0

    init(minimumInterval: TimeInterval, maximumAge: TimeInterval) {
        self.minimumInterval = minimumInterval
        self.maximumAge = maximumAge
    }

    mutating func offer(_ request: WheelShortcutRequest) {
        // Replace rather than append, including when the direction changes.
        pending = request
    }

    mutating func cancel() {
        pending = nil
    }

    mutating func next(at now: TimeInterval) -> Action {
        guard let request = pending else { return .idle }
        guard now - request.receivedAt <= maximumAge else {
            pending = nil
            return .idle
        }
        if now < nextAllowedAt { return .wait(nextAllowedAt - now) }
        pending = nil
        nextAllowedAt = now + minimumInterval
        return .send(request)
    }
}

final class WheelShortcutScheduler: @unchecked Sendable {
    private let queue: DispatchQueue
    private let post: @Sendable (WheelShortcutRequest) -> Void
    private let lock = NSLock()
    private var scheduled = false
    private var buffer = WheelShortcutBuffer(minimumInterval: 0.18, maximumAge: 0.2)

    init(queue: DispatchQueue, post: @escaping @Sendable (WheelShortcutRequest) -> Void) {
        self.queue = queue
        self.post = post
    }

    func submit(inputID: String, shortcut: ShortcutBinding) {
        lock.lock()
        buffer.offer(WheelShortcutRequest(inputID: inputID, shortcut: shortcut, receivedAt: Self.now))
        let shouldSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if shouldSchedule { queue.async { [weak self] in self?.drain() } }
    }

    func cancel() {
        lock.lock()
        buffer.cancel()
        lock.unlock()
    }

    private func drain() {
        lock.lock()
        let action = buffer.next(at: Self.now)
        if case .idle = action { scheduled = false }
        lock.unlock()

        switch action {
        case .idle:
            return
        case .wait(let delay):
            // Only one drain is scheduled; incoming events update the one slot.
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.drain() }
        case .send(let request):
            post(request)
            queue.async { [weak self] in self?.drain() }
        }
    }

    private static var now: TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
