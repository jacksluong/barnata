import Foundation

public let barnataMachServiceName = "io.jackyluong.barnata.daemon"
public let barnataAppBundleIdentifier = "io.jackyluong.barnata"
public let barnataKanataIdentifier = "io.jackyluong.barnata.kanata"

/// Code signing requirement a peer must satisfy, given the build's Team ID
public func barnataCodeSigningRequirement(teamID: String, identifier: String) -> String {
    "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(identifier)\""
}

@objc public protocol BarnataDaemonProtocol {
    func version(reply: @escaping (String) -> Void)
    func status(reply: @escaping (Data) -> Void)
    func start(request: Data, reply: @escaping (Data) -> Void)
    func stop(reply: @escaping (Data) -> Void)
    func restart(reply: @escaping (Data) -> Void)
    func checkConfig(request: Data, reply: @escaping (Data) -> Void)
    func ensureVirtualHIDDaemon(reply: @escaping (Data) -> Void)
    func activateDriver(reply: @escaping (Data) -> Void)
    func subscribe(client: NSXPCListenerEndpoint)
}

@objc public protocol BarnataClientProtocol {
    func statusDidChange(status: Data)
}
