import Foundation
import XCTest

@testable import BarnataCore

final class ConfigWriterTests: XCTestCase {
    func testReplacesAnExistingKeyInPlace() {
        let text = """
        [app]
        launch_at_login = true
        show_dock_icon = false
        """
        XCTAssertEqual(
            ConfigWriter.setting(.showDockIcon, to: true, in: text),
            """
            [app]
            launch_at_login = true
            show_dock_icon = true
            """
        )
    }

    func testKeepsIndentationAndTheTrailingComment() {
        let text = "[app]\n  show_dock_icon   = false   # writable by the menu"
        XCTAssertEqual(
            ConfigWriter.setting(.showDockIcon, to: true, in: text),
            "[app]\n  show_dock_icon   = true   # writable by the menu"
        )
    }

    func testAHashInsideAStringIsNotATrailingComment() {
        let text = "[app]\nstatus_icons = \"a#b\"\nshow_dock_icon = false"
        let result = ConfigWriter.setting(.showDockIcon, to: true, in: text)
        XCTAssertTrue(result.contains("status_icons = \"a#b\""))
        XCTAssertTrue(result.contains("show_dock_icon = true"))
    }

    func testPreservesCommentsAndOrderOfEveryOtherLine() {
        let text = """
        # Barnata config
        [app]
        # toggled from the menu
        launch_at_login = false

        [defaults]
        tcp_port = 5829

        [presets."Default"]
        kanata_config = "~/.config/kanata/canary.kbd"
        autorun = true
        """
        let result = ConfigWriter.setting(.launchAtLogin, to: true, in: text)
        XCTAssertEqual(
            result,
            text.replacingOccurrences(of: "launch_at_login = false", with: "launch_at_login = true")
        )
    }

    func testAppendsAMissingKeyAsTheLastLineOfTheTable() {
        let text = """
        [app]
        launch_at_login = true

        [defaults]
        tcp_port = 5829
        """
        XCTAssertEqual(
            ConfigWriter.setting(.showDockIcon, to: true, in: text),
            """
            [app]
            launch_at_login = true
            show_dock_icon = true

            [defaults]
            tcp_port = 5829
            """
        )
    }

    func testAppendsToAnEmptyAppTable() {
        let text = "[app]\n\n[defaults]\ntcp_port = 5829"
        XCTAssertEqual(
            ConfigWriter.setting(.showDockIcon, to: true, in: text),
            "[app]\nshow_dock_icon = true\n\n[defaults]\ntcp_port = 5829"
        )
    }

    func testInsertsTheAppTableAtTheTopWhenItIsMissing() {
        let text = """
        [defaults]
        tcp_port = 5829
        """
        XCTAssertEqual(
            ConfigWriter.setting(.showDockIcon, to: true, in: text),
            """
            [app]
            show_dock_icon = true

            [defaults]
            tcp_port = 5829
            """
        )
    }

    func testAKeyOfTheSameNameInAnotherTableIsLeftAlone() {
        let text = """
        [defaults]
        show_dock_icon = false

        [app]
        show_dock_icon = false
        """
        let result = ConfigWriter.setting(.showDockIcon, to: true, in: text)
        XCTAssertEqual(
            result,
            """
            [defaults]
            show_dock_icon = false

            [app]
            show_dock_icon = true
            """
        )
    }

    func testTheResultOfAWriteStillParses() throws {
        let written = ConfigWriter.setting(.showDockIcon, to: true, in: fullConfigExample)
        let config = try parseConfig(written)
        XCTAssertTrue(config.app.showDockIcon)
        XCTAssertEqual(config.app.launchAtLogin, true)
        XCTAssertEqual(config.presets.map(\.name), ["Default"])
    }

    func testRoundTripThroughTheFileWriterIsAtomicAndReportsAModificationDate() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "config.toml")
        try fullConfigExample.write(to: url, atomically: true, encoding: .utf8)

        let writer = ConfigFileWriter(url: url)
        let date = try writer.set(.showDockIcon, to: true)

        XCTAssertNotNil(date)
        let reloaded = try ConfigLoader.load(from: url, home: testHome)
        XCTAssertTrue(reloaded.app.showDockIcon)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers, ["config.toml"])
    }
}
