// swift-tools-version: 6.0
import PackageDescription

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
        .executableTarget(name: "Barnata", dependencies: ["BarnataAppKit"]),
        .executableTarget(name: "SettingsPreview", dependencies: ["BarnataAppKit"]),
        .target(name: "BarnataDaemonKit", dependencies: ["BarnataCore"]),
        .executableTarget(name: "barnata-daemon", dependencies: ["BarnataDaemonKit"]),
        .testTarget(name: "BarnataCoreTests", dependencies: ["BarnataCore"]),
        .testTarget(name: "BarnataAppKitTests", dependencies: ["BarnataAppKit"]),
        .testTarget(name: "BarnataDaemonKitTests", dependencies: ["BarnataDaemonKit"]),
    ]
)
