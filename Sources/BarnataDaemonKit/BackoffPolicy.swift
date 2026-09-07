import Foundation

/// Restart delays after a crash, and the rule for when to stop trying
public struct BackoffPolicy: Sendable, Equatable {
    public enum Decision: Sendable, Equatable {
        case restart(after: TimeInterval)
        case giveUp
    }

    public static let defaultDelays: [TimeInterval] = [1, 2, 4, 8, 30]
    public static let defaultMaxRestarts = 5
    public static let defaultWindow: TimeInterval = 120

    public let delays: [TimeInterval]
    public let maxRestarts: Int
    public let window: TimeInterval

    private var windowStart: Date?
    private var crashCount = 0

    public init(
        delays: [TimeInterval] = BackoffPolicy.defaultDelays,
        maxRestarts: Int = BackoffPolicy.defaultMaxRestarts,
        window: TimeInterval = BackoffPolicy.defaultWindow
    ) {
        self.delays = delays
        self.maxRestarts = maxRestarts
        self.window = window
    }

    /// Delay before the nth restart, 1-based, holding at the last value
    public func delay(forCrash crash: Int) -> TimeInterval {
        guard !delays.isEmpty else { return 0 }
        return delays[min(max(crash, 1), delays.count) - 1]
    }

    public var restartCount: Int { crashCount }

    public mutating func recordCrash(at date: Date = Date()) -> Decision {
        if let windowStart, date.timeIntervalSince(windowStart) >= window { reset() }
        if windowStart == nil { windowStart = date }
        crashCount += 1
        guard crashCount <= maxRestarts else { return .giveUp }
        return .restart(after: delay(forCrash: crashCount))
    }

    public mutating func reset() {
        windowStart = nil
        crashCount = 0
    }
}
