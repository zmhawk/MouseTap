import Foundation
import XCTest
@testable import MouseEventProbe

final class WheelShortcutBufferTests: XCTestCase {
    private func request(_ input: String = "scroll.right", at time: TimeInterval) throws -> WheelShortcutRequest {
        let code = input == "scroll.left" ? 123 : 124
        let data = Data("{\"keyCode\":\(code),\"command\":false,\"option\":false,\"control\":true,\"shift\":false,\"keyName\":\"arrow\"}".utf8)
        return WheelShortcutRequest(inputID: input, shortcut: try JSONDecoder().decode(ShortcutBinding.self, from: data), receivedAt: time)
    }

    func testBurstHasOnlyOnePendingShortcut() throws {
        var buffer = WheelShortcutBuffer(minimumInterval: 0.18, maximumAge: 0.2)
        for _ in 0..<10_000 { buffer.offer(try request(at: 1)) }
        guard case .send = buffer.next(at: 1) else { return XCTFail("Fresh event should send") }
        guard case .idle = buffer.next(at: 1) else { return XCTFail("Burst must not leave a backlog") }
    }

    func testRateLimitAndDirectionReplacement() throws {
        var buffer = WheelShortcutBuffer(minimumInterval: 0.18, maximumAge: 0.2)
        buffer.offer(try request(at: 1))
        guard case .send = buffer.next(at: 1) else { return XCTFail() }
        buffer.offer(try request(at: 1.01))
        guard case .wait(let delay) = buffer.next(at: 1.02) else { return XCTFail("Too soon") }
        XCTAssertEqual(delay, 0.16, accuracy: 0.00001)
        buffer.offer(try request("scroll.left", at: 1.10))
        guard case .send(let latest) = buffer.next(at: 1.181) else { return XCTFail() }
        XCTAssertEqual(latest.inputID, "scroll.left")
        guard case .idle = buffer.next(at: 1.4) else { return XCTFail("No trailing burst") }
    }

    func testExpiredAndCancelledRequestsNeverSend() throws {
        var buffer = WheelShortcutBuffer(minimumInterval: 0.18, maximumAge: 0.2)
        buffer.offer(try request(at: 1))
        guard case .idle = buffer.next(at: 1.201) else { return XCTFail("Stale request") }
        buffer.offer(try request(at: 2))
        buffer.cancel()
        guard case .idle = buffer.next(at: 2) else { return XCTFail("Cancelled request") }
        buffer.offer(try request(at: 3))
        guard case .send = buffer.next(at: 3) else { return XCTFail("Cancel must allow new input") }
    }

    func testContinuousLongPressRemainsBounded() throws {
        var buffer = WheelShortcutBuffer(minimumInterval: 0.18, maximumAge: 0.2)
        var sent = 0
        // Simulate 1,000 input events per second for ten seconds.
        for tick in 0..<10_000 {
            let time = 1 + Double(tick) / 1_000
            buffer.offer(try request(at: time))
            if case .send = buffer.next(at: time) { sent += 1 }
        }
        XCTAssertGreaterThan(sent, 50)
        XCTAssertLessThanOrEqual(sent, 56)
        // At most one additional request can follow release.
        _ = buffer.next(at: 11.19)
        XCTAssertNil(buffer.pending)
    }
    func testSchedulerCoalescesBurstBeforeWorkerStarts() throws {
        let queue = DispatchQueue(label: "MouseKit.Tests.Burst")
        let sent = expectation(description: "One send")
        sent.assertForOverFulfill = true
        let scheduler = WheelShortcutScheduler(queue: queue) { request in
            XCTAssertEqual(request.inputID, "scroll.left")
            sent.fulfill()
        }
        let right = try request(at: 0).shortcut
        let left = try request("scroll.left", at: 0).shortcut
        queue.suspend()
        for _ in 0..<10_000 { scheduler.submit(inputID: "scroll.right", shortcut: right) }
        scheduler.submit(inputID: "scroll.left", shortcut: left)
        queue.resume()
        wait(for: [sent], timeout: 1)
        queue.sync {}
    }

    func testSchedulerCancellationAllowsFreshInput() throws {
        let queue = DispatchQueue(label: "MouseKit.Tests.Cancel")
        let sent = expectation(description: "Only fresh input")
        sent.assertForOverFulfill = true
        let scheduler = WheelShortcutScheduler(queue: queue) { request in
            XCTAssertEqual(request.inputID, "scroll.left")
            sent.fulfill()
        }
        let right = try request(at: 0).shortcut
        let left = try request("scroll.left", at: 0).shortcut
        queue.suspend()
        scheduler.submit(inputID: "scroll.right", shortcut: right)
        scheduler.cancel()
        queue.resume()
        queue.sync {}
        scheduler.submit(inputID: "scroll.left", shortcut: left)
        wait(for: [sent], timeout: 1)
        queue.sync {}
    }

}
