import Foundation
import XCTest

@testable import BarnataCore

final class ConfigParsingTests: XCTestCase {
    func testFullExampleParses() throws {
        let config = try parseConfig(fullConfigExample)

        XCTAssertEqual(config.app.launchAtLogin, true)
        XCTAssertFalse(config.app.showDockIcon)
        XCTAssertEqual(config.defaults.layerIcons["base"], "base.png")
        XCTAssertEqual(config.defaults.layerIcons["*"], "default.png")

        let preset = try XCTUnwrap(config.preset(named: "Default"))
        XCTAssertTrue(preset.autorun)
        XCTAssertEqual(preset.configPaths, ["/Users/test/.config/kanata/example.kbd"])
        XCTAssertEqual(preset.layerIcons.count, 10)
        XCTAssertEqual(config.autorunPreset?.name, "Default")
    }

    func testEmptyFileIsValid() throws {
        let config = try parseConfig("")
        XCTAssertTrue(config.presets.isEmpty)
        XCTAssertFalse(config.app.showDockIcon)
        XCTAssertNil(config.app.launchAtLogin)
    }

    func testPresetsKeepFileOrder() throws {
        let config = try parseConfig("""
        [presets."Zulu"]
        kanata_config = "/tmp/z.kbd"

        [presets."alpha"]
        kanata_config = "/tmp/a.kbd"

        [presets."Mike"]
        kanata_config = "/tmp/m.kbd"
        """)
        XCTAssertEqual(config.presets.map(\.name), ["Zulu", "alpha", "Mike"])
    }

    func testPresetsWithBareAndInlineHeadersKeepFileOrder() throws {
        let config = try parseConfig("""
        [presets.gaming]
        kanata_config = "/tmp/g.kbd"

        [presets."Work Laptop"]   # trailing comment
        kanata_config = "/tmp/w.kbd"
        """)
        XCTAssertEqual(config.presets.map(\.name), ["gaming", "Work Laptop"])
    }

    func testMalformedTOMLFails() {
        XCTAssertThrowsError(try parseConfig("[app\n")) { error in
            XCTAssertTrue("\(error)".contains("invalid TOML"), "\(error)")
        }
    }
}

final class UnknownKeyTests: XCTestCase {
    func testTopLevelUnknownKeyFails() {
        assertConfigError("[general]\nfoo = 1") { error in
            XCTAssertEqual(error.keyPath, "general")
            XCTAssertEqual(error.reason, "unknown key")
        }
    }

    func testUnknownKeyInsideAppFails() {
        assertConfigError("[app]\nhooks = true") { error in
            XCTAssertEqual(error.description, "app.hooks: unknown key")
        }
    }

    func testUnknownKeyInsideDefaultsFails() {
        assertConfigError("[defaults]\nkanata_executable = \"/usr/local/bin/kanata\"") { error in
            XCTAssertEqual(error.description, "defaults.kanata_executable: unknown key")
        }
    }

    func testUnknownKeyInsidePresetFails() {
        assertConfigError("""
        [presets."Default"]
        kanata_config = "/tmp/a.kbd"
        extra_env = { FOO = "bar" }
        """) { error in
            XCTAssertEqual(error.description, "presets.Default.extra_env: unknown key")
        }
    }
}

final class PathTests: XCTestCase {
    func testTildeExpansion() throws {
        let config = try parseConfig("""
        [presets."P"]
        kanata_config = "~/keys/example.kbd"
        """)
        XCTAssertEqual(config.presets[0].configPaths, ["/Users/test/keys/example.kbd"])
    }

    func testRelativePathResolvesAgainstConfigDirectory() throws {
        let config = try parseConfig("""
        [presets."P"]
        kanata_config = "kbd/example.kbd"
        """)
        XCTAssertEqual(config.presets[0].configPaths, ["/Users/test/.config/barnata/kbd/example.kbd"])
    }

    func testAbsolutePathIsStandardized() throws {
        let config = try parseConfig("""
        [presets."P"]
        kanata_config = "/etc/kanata/../kanata/example.kbd"
        """)
        XCTAssertEqual(config.presets[0].configPaths, ["/etc/kanata/example.kbd"])
    }

    func testBareTildeIsHome() {
        XCTAssertEqual(ConfigPath.expand("~", home: testHome, relativeTo: testConfigDirectory), "/Users/test")
    }

    func testTildeInsideAPathIsNotExpanded() {
        let expanded = ConfigPath.expand("/tmp/~/a.kbd", home: testHome, relativeTo: testConfigDirectory)
        XCTAssertEqual(expanded, "/tmp/~/a.kbd")
    }
}

final class KanataConfigShapeTests: XCTestCase {
    func testSingleStringGivesOnePath() throws {
        let preset = try parseConfig("""
        [presets."P"]
        kanata_config = "/tmp/a.kbd"
        """).presets[0]
        XCTAssertEqual(preset.configPaths, ["/tmp/a.kbd"])
        XCTAssertFalse(preset.supportsConfigCycling)
    }

    func testArrayGivesEveryPathInOrder() throws {
        let preset = try parseConfig("""
        [presets."P"]
        kanata_config = ["/tmp/a.kbd", "~/b.kbd"]
        """).presets[0]
        XCTAssertEqual(preset.configPaths, ["/tmp/a.kbd", "/Users/test/b.kbd"])
        XCTAssertTrue(preset.supportsConfigCycling)
    }

    func testMissingKanataConfigFails() {
        assertConfigError("[presets.\"P\"]\nautorun = true") { error in
            XCTAssertEqual(error.keyPath, "presets.P.kanata_config")
        }
    }

    func testEmptyArrayFails() {
        assertConfigError("[presets.\"P\"]\nkanata_config = []") { error in
            XCTAssertEqual(error.keyPath, "presets.P.kanata_config")
        }
    }

    func testNonStringArrayElementNamesTheIndex() {
        assertConfigError("""
        [presets."P"]
        kanata_config = ["/tmp/a.kbd", 7]
        """) { error in
            XCTAssertEqual(error.keyPath, "presets.P.kanata_config[1]")
        }
    }
}

final class InheritanceTests: XCTestCase {
    func testPresetInheritsEveryDefault() throws {
        let preset = try parseConfig("""
        [defaults]
        autorestart_on_crash = true
        extra_args = ["--debug"]

        [defaults.layer_icons]
        base = "base.png"

        [presets."P"]
        kanata_config = "/tmp/a.kbd"
        """).presets[0]

        XCTAssertTrue(preset.autorestartOnCrash)
        XCTAssertEqual(preset.extraArgs, ["--debug"])
        XCTAssertEqual(preset.layerIcons, ["base": "base.png"])
    }

    func testPresetOverridesWin() throws {
        let preset = try parseConfig("""
        [defaults]
        autorestart_on_crash = true

        [presets."P"]
        kanata_config = "/tmp/a.kbd"
        autorestart_on_crash = false
        """).presets[0]

        XCTAssertFalse(preset.autorestartOnCrash)
    }

    func testLayerIconsReplaceRatherThanMerge() throws {
        let config = try parseConfig("""
        [defaults.layer_icons]
        base = "base.png"
        typing = "typing.png"
        "*" = "default.png"

        [presets."Inherits"]
        kanata_config = "/tmp/a.kbd"

        [presets."Overrides"]
        kanata_config = "/tmp/b.kbd"
        layer_icons = { base = "other.png" }
        """)

        XCTAssertEqual(config.preset(named: "Inherits")?.layerIcons.count, 3)
        XCTAssertEqual(config.preset(named: "Overrides")?.layerIcons, ["base": "other.png"])
        XCTAssertNil(config.preset(named: "Overrides")?.iconSymbol(forLayer: "typing"))
        XCTAssertEqual(config.preset(named: "Inherits")?.iconSymbol(forLayer: "typing"), "typing.png")
    }

    func testUnknownLayerFallsBackToStar() throws {
        let preset = try parseConfig("""
        [presets."P"]
        kanata_config = "/tmp/a.kbd"
        layer_icons = { base = "base.png", "*" = "default.png" }
        """).presets[0]

        XCTAssertEqual(preset.iconSymbol(forLayer: "base"), "base.png")
        XCTAssertEqual(preset.iconSymbol(forLayer: "whatever"), "default.png")
    }
}

final class ValidationTests: XCTestCase {
    func testDisallowedExtraArgNamesTheFlag() {
        assertConfigError("[defaults]\nextra_args = [\"--danger\"]") { error in
            XCTAssertEqual(error.keyPath, "defaults.extra_args")
            XCTAssertTrue(error.reason.contains("--danger"), error.reason)
        }
    }

    func testDisallowedFlagInPresetNamesThePresetPath() {
        assertConfigError("""
        [presets."P"]
        kanata_config = "/tmp/a.kbd"
        extra_args = ["--cmd-enabled"]
        """) { error in
            XCTAssertEqual(error.description, "presets.P.extra_args: --cmd-enabled is not an allowed kanata flag")
        }
    }

    func testTCPPortIsNoLongerAConfigKey() {
        assertConfigError("[defaults]\ntcp_port = 5829") { error in
            XCTAssertEqual(error.description, "defaults.tcp_port: unknown key")
        }
    }

    func testTwoAutorunPresetsFail() {
        assertConfigError("""
        [presets."A"]
        kanata_config = "/tmp/a.kbd"
        autorun = true

        [presets."B"]
        kanata_config = "/tmp/b.kbd"
        autorun = true
        """) { error in
            XCTAssertTrue(error.reason.contains("at most one preset"), error.reason)
        }
    }

    func testWrongTypeNamesTheExpectedType() {
        assertConfigError("[app]\nshow_dock_icon = \"yes\"") { error in
            XCTAssertEqual(error.description, "app.show_dock_icon: expected true or false")
        }
    }

    func testTopLevelKeysMustBeTables() {
        for (text, expected) in [
            ("app = 5", "app: expected a table"),
            ("defaults = \"x\"", "defaults: expected a table"),
            ("presets = 5", "presets: expected a table"),
        ] {
            assertConfigError(text) { error in
                XCTAssertEqual(error.description, expected)
            }
        }
    }
}

final class ConfigLocationTests: XCTestCase {
    func testDefaultPath() {
        let url = ConfigLoader.defaultURL(environment: [:], home: testHome)
        XCTAssertEqual(url.path, "/Users/test/.config/barnata/config.toml")
    }

    func testEnvironmentOverride() {
        let url = ConfigLoader.defaultURL(
            environment: [ConfigLoader.environmentKey: "~/elsewhere/barnata.toml"],
            home: testHome
        )
        XCTAssertEqual(url.path, "/Users/test/elsewhere/barnata.toml")
    }

    func testLoadFromDisk() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appending(path: "config.toml")
        try fullConfigExample.write(to: file, atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(from: file, home: testHome)
        XCTAssertEqual(config.presets.map(\.name), ["Default"])
    }

    func testMissingFileReportsThePath() {
        XCTAssertThrowsError(try ConfigLoader.load(from: URL(fileURLWithPath: "/nope/config.toml"), home: testHome)) {
            XCTAssertTrue("\($0)".contains("/nope/config.toml"), "\($0)")
        }
    }

    func testLoadCreatesTheFileAndItsDirectory() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appending(path: "barnata/config.toml")
        let config = try ConfigLoader.load(from: file, home: testHome)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), ConfigLoader.template)
        XCTAssertEqual(config.presets, [])
        XCTAssertFalse(config.app.showDockIcon)
    }

    func testLoadLeavesAnExistingFileAlone() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appending(path: "config.toml")
        try fullConfigExample.write(to: file, atomically: true, encoding: .utf8)

        _ = try ConfigLoader.load(from: file, home: testHome)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), fullConfigExample)
    }

    func testWritingToAMissingFileStartsFromTheTemplate() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appending(path: "barnata/config.toml")
        try ConfigFileWriter(url: file).set(.showDockIcon, to: true)

        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("[defaults]"), text)
        XCTAssertEqual(try ConfigLoader.load(from: file, home: testHome).app.showDockIcon, true)
    }
}
