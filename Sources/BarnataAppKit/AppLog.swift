import BarnataCore
import Foundation
import os

let log = Logger(subsystem: barnataAppBundleIdentifier, category: "app")

/// `DaemonClient` and `KanataTCPClient` deliver every callback on the main queue, so the hop is already done
func onMain<T: Sendable>(_ body: @escaping @MainActor (T) -> Void) -> @Sendable (T) -> Void {
    { value in MainActor.assumeIsolated { body(value) } }
}

func onMain(_ body: @escaping @MainActor () -> Void) -> @Sendable () -> Void {
    { MainActor.assumeIsolated(body) }
}
