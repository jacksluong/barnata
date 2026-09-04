import Foundation
import XCTest

@testable import BarnataCore

final class IconResolverTests: XCTestCase {
    private let resolver = IconResolver(configDirectory: testConfigDirectory)

    func testRelativeIconResolvesAgainstTheIconsDirectory() {
        XCTAssertEqual(
            resolver.url(forIconFile: "base.png").path,
            "/Users/test/.config/barnata/icons/base.png"
        )
    }

    func testAbsoluteIconPathIsUsedAsIs() {
        XCTAssertEqual(resolver.url(forIconFile: "/tmp/base.png").path, "/tmp/base.png")
    }

    func testLayerResolvesThroughThePresetTable() {
        let preset = Preset(
            name: "P",
            configPaths: ["/tmp/a.kbd"],
            layerIcons: ["base": "base.png", "*": "default.png"]
        )
        XCTAssertEqual(resolver.layerIconURL(forLayer: "base", in: preset)?.lastPathComponent, "base.png")
        XCTAssertEqual(resolver.layerIconURL(forLayer: "unknown", in: preset)?.lastPathComponent, "default.png")
    }

    func testPresetWithoutIconsResolvesNothing() {
        let preset = Preset(name: "P", configPaths: ["/tmp/a.kbd"])
        XCTAssertNil(resolver.layerIconURL(forLayer: "base", in: preset))
    }

    func testTemplateSuffixDetection() {
        let cases = [("baseTemplate.png", true), ("base.png", false), ("Template.pdf", true), ("templates.png", false)]
        for (fileName, expected) in cases {
            XCTAssertEqual(IconResolver.isTemplate(fileName: fileName), expected, fileName)
        }
    }

    func testStatusIconOverridesAreFoundInTheConfiguredDirectory() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let overrides = root.appending(path: "icons/status-icons")
        try FileManager.default.createDirectory(at: overrides, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data().write(to: overrides.appending(path: "defaultTemplate.png"))
        try Data().write(to: overrides.appending(path: "crashed.png"))

        let resolver = IconResolver(configDirectory: root, statusIcons: "status-icons")
        XCTAssertEqual(resolver.statusIconURL(.normal)?.lastPathComponent, "defaultTemplate.png")
        XCTAssertEqual(resolver.statusIconURL(.crashed)?.lastPathComponent, "crashed.png")
        XCTAssertNil(resolver.statusIconURL(.paused))
    }

    func testWithoutAStatusIconsDirectoryNothingIsOverridden() {
        XCTAssertNil(resolver.statusIconsDirectory)
        for icon in IconResolver.StatusIcon.allCases {
            XCTAssertNil(resolver.statusIconURL(icon), icon.rawValue)
        }
    }

    func testResolverBuiltFromAConfigPicksUpTheStatusIconsSetting() throws {
        let config = try parseConfig("[app]\nstatus_icons = \"status-icons\"")
        let resolver = IconResolver(config: config, configURL: testConfigDirectory.appending(path: "config.toml"))
        XCTAssertEqual(
            resolver.statusIconsDirectory?.path,
            "/Users/test/.config/barnata/icons/status-icons"
        )
    }
}
