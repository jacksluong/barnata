import BarnataCore
import Darwin
import Foundation

/// Installs, activates, and supervises the Karabiner DriverKit virtual HID device
public final class DriverManager: @unchecked Sendable {
    public static let supportRoot = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
    public static let daemonPath =
        "\(supportRoot)/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    public static let daemonInfoPlistPath =
        "\(supportRoot)/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/Info.plist"
    public static let managerPath =
        "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
    public static let dextIdentifier = "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"
    /// PROC_PIDPATHINFO_MAXSIZE, which is a macro Swift does not import
    private static let maxProcessPathLength = 4 * Int(MAXPATHLEN)

    private let layout: BundleLayout
    private let requirements: DriverRequirements
    private let pqrsRequirement: String
    private let supervisor: ProcessSupervisor

    public init(layout: BundleLayout, requirements: DriverRequirements, spawner: Spawner, logWriter: LogWriter?) {
        self.layout = layout
        self.requirements = requirements
        self.pqrsRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(SignatureCheck.pqrsTeamID)\""
        self.supervisor = ProcessSupervisor(
            configuration: ProcessSupervisor.Configuration(
                executablePath: DriverManager.daemonPath,
                requirement: pqrsRequirement
            ),
            spawner: spawner,
            logWriter: logWriter
        )
    }

    public var status: DriverStatus {
        let installedVersion = installedDriverVersion()
        let runningPID = runningVirtualHIDDaemonPID()
        return DriverStatus(
            installed: FileManager.default.fileExists(atPath: DriverManager.daemonPath),
            version: installedVersion,
            requiredVersion: requirements.requiredVersion,
            activated: isDriverExtensionActivated(),
            vhidDaemonRunning: runningPID != nil,
            vhidDaemonManagedByBarnata: runningPID != nil && runningPID == supervisor.snapshot.pid
        )
    }

    /// Runs the virtual HID daemon unless something else already owns it
    @discardableResult
    public func ensureVirtualHIDDaemon() -> CommandResult {
        if runningVirtualHIDDaemonPID() != nil { return CommandResult(ok: true, message: "already running") }
        guard FileManager.default.fileExists(atPath: DriverManager.daemonPath) else {
            return .failure("the Karabiner virtual HID driver is not installed")
        }

        let request = ValidatedStartRequest(
            presetName: "Karabiner-VirtualHIDDevice-Daemon",
            configPaths: [],
            extraArgs: [],
            autorestartOnCrash: true,
            ownerUID: 0,
            arguments: []
        )
        return supervisor.start(request)
    }

    public func stopVirtualHIDDaemon() {
        supervisor.stop()
    }

    public func terminateVirtualHIDDaemon() {
        supervisor.terminateNow()
    }

    public func installDriver() -> CommandResult {
        if let installed = installedDriverVersion(),
           compareVersions(installed, requirements.requiredVersion) == .orderedDescending {
            return .failure(
                "the installed driver \(installed) is newer than the required \(requirements.requiredVersion), "
                    + "leaving it alone"
            )
        }

        let packagePath = layout.driverPackageURL(named: requirements.packageName).path
        do {
            try SignatureCheck.validatePackage(path: packagePath, teamID: SignatureCheck.pqrsTeamID)
        } catch {
            return .failure("refusing to install the driver: \(error)")
        }

        log.notice("installing \(packagePath, privacy: .public)")
        let result = Command.run("/usr/sbin/installer", ["-pkg", packagePath, "-target", "/"])
        guard result.exitCode == 0 else {
            return CommandResult(ok: false, message: "installer failed", output: result.combinedOutput)
        }

        let activation = activateDriver()
        return CommandResult(
            ok: activation.ok,
            message: activation.ok ? "installed \(requirements.requiredVersion)" : activation.message,
            output: result.combinedOutput + (activation.output ?? "")
        )
    }

    public func activateDriver() -> CommandResult {
        do {
            try SignatureCheck.validate(path: DriverManager.managerPath, requirement: pqrsRequirement)
        } catch {
            return .failure("refusing to run the Karabiner manager: \(error)")
        }

        let result = Command.run(DriverManager.managerPath, ["activate"])
        guard result.exitCode == 0 else {
            return CommandResult(ok: false, message: "activation failed", output: result.combinedOutput)
        }
        return CommandResult(ok: true, message: "activation requested, approve it in System Settings", output: result.combinedOutput)
    }

    // MARK: - Inspection

    private func installedDriverVersion() -> String? {
        guard let data = FileManager.default.contents(atPath: DriverManager.daemonInfoPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String
    }

    private func isDriverExtensionActivated() -> Bool {
        let result = Command.run("/usr/bin/systemextensionsctl", ["list"])
        guard result.exitCode == 0 else { return false }
        return result.combinedOutput
            .split(separator: "\n")
            .contains { $0.contains(DriverManager.dextIdentifier) && $0.contains("activated") && $0.contains("enabled") }
    }

    /// pid of any process running the pqrs virtual HID daemon binary, whoever started it
    private func runningVirtualHIDDaemonPID() -> pid_t? {
        let capacity = Int(proc_listallpids(nil, 0))
        guard capacity > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: capacity)
        let byteCount = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard byteCount > 0 else { return nil }

        var pathBuffer = [UInt8](repeating: 0, count: DriverManager.maxProcessPathLength)
        for pid in pids.prefix(Int(byteCount) / MemoryLayout<pid_t>.size) where pid > 0 {
            let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard length > 0 else { continue }
            if String(decoding: pathBuffer[0..<Int(length)], as: UTF8.self) == DriverManager.daemonPath { return pid }
        }
        return nil
    }

    /// Numeric dotted comparison, so 6.10.0 sorts above 6.8.0
    func compareVersions(_ left: String, _ right: String) -> ComparisonResult {
        let leftParts = left.split(separator: ".").map { Int($0) ?? 0 }
        let rightParts = right.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(leftParts.count, rightParts.count) {
            let a = index < leftParts.count ? leftParts[index] : 0
            let b = index < rightParts.count ? rightParts[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
