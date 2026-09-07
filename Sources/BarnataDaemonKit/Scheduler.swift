import Foundation

/// Delayed work, injected so backoff and termination timeouts are testable without sleeping
public protocol Scheduler: Sendable {
    func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () -> Void)
}

public struct QueueScheduler: Scheduler {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = DispatchQueue.global(qos: .utility)) {
        self.queue = queue
    }

    public func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
