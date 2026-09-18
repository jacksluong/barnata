// swift-tools-version: 6.0
import PackageDescription
import Foundation

let minimumMacOS = "14.0"

/// The macOS SDK version `xcrun` reports, or the minimum when there is no usable toolchain
let installedSDK: String = {
    let xcrun = Process()
    xcrun.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    xcrun.arguments = ["--sdk", "macosx", "--show-sdk-version"]
    let output = Pipe()
    xcrun.standardOutput = output
    xcrun.standardError = FileHandle.nullDevice
    guard (try? xcrun.run()) != nil else { return minimumMacOS }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    xcrun.waitUntilExit()
    guard xcrun.terminationStatus == 0,
          let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !version.isEmpty
    else { return minimumMacOS }
    return version
}()

// SwiftPM stamps the binary's SDK field with the deployment target, and AppKit reads that field to
// pick which generation of controls to draw. Stamping the SDK actually in use keeps the app on the
// newest look every OS it runs on offers, while the minimum stays at macOS 14
let currentDesignSDK: [LinkerSetting] = [
    .unsafeFlags([
        "-Xlinker", "-platform_version",
        "-Xlinker", "macos",
        "-Xlinker", minimumMacOS,
        "-Xlinker", installedSDK,
    ])
]

let package = Package(
    name: "barnata",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BarnataCore", targets: ["BarnataCore"]),
        .library(name: "BarnataDaemonKit", targets: ["BarnataDaemonKit"]),
        .library(name: "BarnataAppKit", targets: ["BarnataAppKit"]),
        .executable(name: "Barnata", targets: ["Barnata"]),
        .executable(name: "barnata-daemon", targets: ["barnata-daemon"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "BarnataCore",
            dependencies: [.product(name: "TOMLKit", package: "TOMLKit")]
        ),
        .target(name: "BarnataAppKit", dependencies: ["BarnataCore"]),
        .executableTarget(name: "Barnata", dependencies: ["BarnataAppKit"], linkerSettings: currentDesignSDK),
        .executableTarget(name: "SettingsPreview", dependencies: ["BarnataAppKit"], linkerSettings: currentDesignSDK),
        .target(name: "BarnataDaemonKit", dependencies: ["BarnataCore"]),
        .executableTarget(name: "barnata-daemon", dependencies: ["BarnataDaemonKit"], linkerSettings: currentDesignSDK),
        .testTarget(name: "BarnataCoreTests", dependencies: ["BarnataCore"]),
        .testTarget(name: "BarnataAppKitTests", dependencies: ["BarnataAppKit"]),
        .testTarget(name: "BarnataDaemonKitTests", dependencies: ["BarnataDaemonKit"]),
    ]
)
