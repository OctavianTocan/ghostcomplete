import Foundation

final class Debouncer {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private var item: DispatchWorkItem?

    init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    func schedule(_ action: @escaping () -> Void) {
        schedule(after: delay, action)
    }

    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        item?.cancel()
        let next = DispatchWorkItem(block: action)
        item = next
        queue.asyncAfter(deadline: .now() + delay, execute: next)
    }

    func cancel() {
        item?.cancel()
        item = nil
    }
}
