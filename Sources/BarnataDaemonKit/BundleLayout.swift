import BarnataCore
import Foundation

/// Paths inside the daemon's own app bundle, never taken from a request
public struct BundleLayout: Sendable, Equatable {
    public static let logDirectory = URL(fileURLWithPath: "/Library/Logs/Barnata")
    public static let kanataLogName = "kanata.log"

    public let executableURL: URL

    public init(executableURL: URL) {
        self.executableURL = executableURL.standardizedFileURL
    }

    public init(processInfo: ProcessInfo = .processInfo) {
        self.init(executableURL: URL(fileURLWithPath: processInfo.arguments.first ?? "").standardizedFileURL)
    }

    /// Contents/MacOS
    public var macOSDirectory: URL { executableURL.deletingLastPathComponent() }

    /// Contents/Resources
    public var resourcesDirectory: URL {
        macOSDirectory.deletingLastPathComponent().appending(path: "Resources")
    }

    public var kanataURL: URL { macOSDirectory.appending(path: "kanata") }

    public var driverRequirementsURL: URL { resourcesDirectory.appending(path: "driver-requirements.json") }

    public var kanataLogURL: URL { BundleLayout.logDirectory.appending(path: BundleLayout.kanataLogName) }

    public func driverPackageURL(named name: String) -> URL { resourcesDirectory.appending(path: name) }
}

/// Required driver version and pkg file name, read from Contents/Resources/driver-requirements.json
public struct DriverRequirements: Codable, Sendable, Equatable {
    public var requiredVersion: String
    public var packageName: String

    public init(requiredVersion: String, packageName: String) {
        self.requiredVersion = requiredVersion
        self.packageName = packageName
    }

    public static func load(from url: URL) -> DriverRequirements? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DriverRequirements.self, from: data)
    }
}
