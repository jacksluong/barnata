import AppKit
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

/// `NSApp.terminate` from a run loop callout rather than the caller's stack. `.terminateLater`
/// waits on daemon replies that arrive on the main queue, which cannot drain inside a main queue block.
@MainActor
func terminateApp() {
    RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
}
