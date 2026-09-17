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
        autorestart_on_crash = false

        [presets."Default"]
        kanata_config = "~/.config/kanata/example.kbd"
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
        autorestart_on_crash = false
        """
        XCTAssertEqual(
            ConfigWriter.setting(.showDockIcon, to: true, in: text),
            """
            [app]
            launch_at_login = true
            show_dock_icon = true

            [defaults]
            autorestart_on_crash = false
            """
        )
    }

    func testAppendsToAnEmptyAppTable() {
        let text = "[app]\n\n[defaults]\nautorestart_on_crash = false"
        XCTAssertEqual(
            ConfigWriter.setting(.showDockIcon, to: true, in: text),
            "[app]\nshow_dock_icon = true\n\n[defaults]\nautorestart_on_crash = false"
        )
    }

    func testInsertsTheAppTableAtTheTopWhenItIsMissing() {
        let text = """
        [defaults]
        autorestart_on_crash = false
        """
        XCTAssertEqual(
            ConfigWriter.setting(.showDockIcon, to: true, in: text),
            """
            [app]
            show_dock_icon = true

            [defaults]
            autorestart_on_crash = false
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

final class PresetWritingTests: XCTestCase {
    private func edit(_ text: String, _ body: (inout TOMLDocument) -> Void) -> String {
        var document = TOMLDocument(text)
        body(&document)
        return document.text
    }

    func testAddingAPresetStoresThePathAndNothingElse() throws {
        let result = edit(fullConfigExample) {
            ConfigWriter.addPreset("Gaming", configPath: "/Users/test/keys/gaming.kbd", to: &$0)
        }
        let config = try parseConfig(result)
        XCTAssertEqual(config.presets.map(\.name), ["Default", "Gaming"])
        XCTAssertEqual(config.preset(named: "Gaming")?.configPaths, ["/Users/test/keys/gaming.kbd"])
        XCTAssertEqual(config.preset(named: "Gaming")?.autorun, false)
    }

    func testRemovingAPresetLeavesTheRestOfTheFileIntact() throws {
        let added = edit(fullConfigExample) { ConfigWriter.addPreset("Gaming", configPath: "/tmp/g.kbd", to: &$0) }
        let removed = edit(added) { ConfigWriter.removePreset("Gaming", from: &$0) }
        XCTAssertEqual(removed, fullConfigExample)
    }

    func testRenamingAPresetKeepsItsSettings() throws {
        let result = edit(fullConfigExample) { ConfigWriter.renamePreset("Default", to: "Home Row", in: &$0) }
        let config = try parseConfig(result)
        XCTAssertEqual(config.presets.map(\.name), ["Home Row"])
        XCTAssertEqual(config.preset(named: "Home Row")?.autorun, true)
        XCTAssertTrue(result.contains("[presets.\"Home Row\"]"))
    }

    func testTheFirstIconEditMaterializesTheInheritedDefaults() throws {
        let result = edit(fullConfigExample) {
            ConfigWriter.setLayerIcon(
                preset: "Default",
                layer: "base",
                symbol: "command",
                inherited: ["base": "base.png", "typing": "typing.png"],
                in: &$0
            )
        }
        let config = try parseConfig(result)
        XCTAssertEqual(config.preset(named: "Default")?.layerIcons, ["base": "command", "typing": "typing.png"])
        // The defaults table is untouched, so other presets keep inheriting it
        XCTAssertEqual(config.defaults.layerIcons["base"], "base.png")
    }

    func testALaterIconEditOnlyTouchesItsOwnKey() throws {
        let once = edit(fullConfigExample) {
            ConfigWriter.setLayerIcon(preset: "Default", layer: "base", symbol: "command", inherited: [:], in: &$0)
        }
        let twice = edit(once) {
            ConfigWriter.setLayerIcon(preset: "Default", layer: "typing", symbol: "keyboard", inherited: [:], in: &$0)
        }
        let config = try parseConfig(twice)
        XCTAssertEqual(config.preset(named: "Default")?.layerIcons, ["base": "command", "typing": "keyboard"])
    }

    func testClearingAnIconRemovesTheKey() throws {
        let set = edit(fullConfigExample) {
            ConfigWriter.setLayerIcon(preset: "Default", layer: "base", symbol: "command", inherited: [:], in: &$0)
        }
        let cleared = edit(set) {
            ConfigWriter.setLayerIcon(preset: "Default", layer: "base", symbol: nil, inherited: [:], in: &$0)
        }
        XCTAssertEqual(try parseConfig(cleared).preset(named: "Default")?.layerIcons, [:])
    }

    func testAnInlineIconTableIsNormalizedIntoASubTable() throws {
        let text = """
        [presets."P"]
        kanata_config = "/tmp/a.kbd"
        layer_icons = { base = "old.png" }
        """
        let result = edit(text) {
            ConfigWriter.setLayerIcon(
                preset: "P",
                layer: "typing",
                symbol: "keyboard",
                inherited: ["base": "old.png"],
                in: &$0
            )
        }
        XCTAssertFalse(result.contains("layer_icons = {"))
        XCTAssertEqual(
            try parseConfig(result).preset(named: "P")?.layerIcons,
            ["base": "old.png", "typing": "keyboard"]
        )
    }

    func testAPresetNameNeedingQuotesSurvivesEveryOperation() throws {
        let name = #"Jacky's "main""#
        var document = TOMLDocument("")
        ConfigWriter.addPreset(name, configPath: "/tmp/a.kbd", to: &document)
        ConfigWriter.setLayerIcon(preset: name, layer: "base", symbol: "command", inherited: [:], in: &document)

        let config = try parseConfig(document.text)
        XCTAssertEqual(config.presets.map(\.name), [name])
        XCTAssertEqual(config.preset(named: name)?.layerIcons, ["base": "command"])

        ConfigWriter.removePreset(name, from: &document)
        XCTAssertEqual(try parseConfig(document.text).presets, [])
    }

    func testTheFallbackKeyIsWrittenQuoted() throws {
        let result = edit(fullConfigExample) {
            ConfigWriter.setLayerIcon(
                preset: "Default",
                layer: Preset.layerIconFallbackKey,
                symbol: "circle",
                inherited: [:],
                in: &$0
            )
        }
        XCTAssertTrue(result.contains("\"*\" = \"circle\""))
        XCTAssertEqual(try parseConfig(result).preset(named: "Default")?.layerIcons["*"], "circle")
    }
}
