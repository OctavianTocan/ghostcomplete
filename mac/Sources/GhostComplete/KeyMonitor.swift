import ApplicationServices
import Foundation

enum KeyDecision {
    case pass
    case swallow
}

@MainActor
final class KeyMonitor {
    typealias Handler = @MainActor (CGKeyCode, CGEventFlags) -> KeyDecision

    private let handler: Handler
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool {
        eventTap != nil
    }

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() -> Bool {
        precondition(Thread.isMainThread, "KeyMonitor must be installed on the main run loop.")
        if eventTap != nil {
            return true
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard type == .keyDown else {
                    return Unmanaged.passUnretained(event)
                }
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                precondition(Thread.isMainThread, "CGEvent tap callback must run on the main run loop.")
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                let decision = MainActor.assumeIsolated {
                    monitor.handler(keyCode, flags)
                }
                switch decision {
                case .pass:
                    return Unmanaged.passUnretained(event)
                case .swallow:
                    return nil
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}
