import CoreFoundation
import Foundation

// Event taps must remain responsive even when AppKit is busy or showing panels.
final class EventTapRunLoop: @unchecked Sendable {
    private var runLoop: CFRunLoop!
    private let source: CFRunLoopSource

    init(source: CFRunLoopSource) {
        self.source = source
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let loop = CFRunLoopGetCurrent()!
            runLoop = loop
            CFRunLoopAddSource(loop, self.source, .commonModes)
            CFRunLoopPerformBlock(loop, "kCFRunLoopDefaultMode" as CFString) { ready.signal() }
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, self.source, .commonModes)
        }
        thread.name = "MouseTap.EventTap"
        thread.qualityOfService = QualityOfService.userInteractive
        thread.start()
        // Ready is signalled from inside the running loop, so stop cannot race startup.
        ready.wait()
    }

    func perform(_ block: @escaping @Sendable () -> Void) {
        CFRunLoopPerformBlock(runLoop, "kCFRunLoopDefaultMode" as CFString, block)
        CFRunLoopWakeUp(runLoop)
    }

    func stop() {
        CFRunLoopStop(runLoop)
        CFRunLoopWakeUp(runLoop)
    }
}
