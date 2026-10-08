import CoreFoundation
import Foundation
import XCTest
@testable import MouseTap

final class EventTapRunLoopTests: XCTestCase {
    func testCallbacksRunWhileMainThreadIsBlockedAndStopReleasesWorker() throws {
        var context = CFRunLoopSourceContext()
        context.perform = { _ in }
        let source = try XCTUnwrap(CFRunLoopSourceCreate(nil, 0, &context))
        var worker: EventTapRunLoop? = EventTapRunLoop(source: source)
        weak var releasedWorker = worker
        let delivered = DispatchSemaphore(value: 0)
        worker?.perform {
            XCTAssertFalse(Thread.isMainThread)
            delivered.signal()
        }
        // No pumping the main run loop: the listener must be independent of it.
        XCTAssertEqual(delivered.wait(timeout: .now() + 1), .success)
        worker?.stop()
        worker = nil
        let deadline = Date().addingTimeInterval(1)
        while releasedWorker != nil && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertNil(releasedWorker, "Stopping must release the listener thread")
    }

    func testRepeatedImmediateStartAndStopDoesNotLeaveThreadsRunning() throws {
        for _ in 0..<50 {
            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            let source = try XCTUnwrap(CFRunLoopSourceCreate(nil, 0, &context))
            var worker: EventTapRunLoop? = EventTapRunLoop(source: source)
            weak var releasedWorker = worker
            worker?.stop()
            worker = nil
            let deadline = Date().addingTimeInterval(1)
            while releasedWorker != nil && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.001)
            }
            XCTAssertNil(releasedWorker)
        }
    }
}
