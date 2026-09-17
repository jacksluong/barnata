import Foundation
import XCTest

@testable import BarnataCore

final class TOMLDocumentTests: XCTestCase {
    func testSettingAKeyLeavesEveryOtherLineAlone() {
        var document = TOMLDocument("""
        # top comment
        [app]
        # about the key
        launch_at_login = false   # trailing

        [defaults]
        autorestart_on_crash = false
        """)
        document.set(.bool(true), forKey: "launch_at_login", inTable: ["app"])

        XCTAssertEqual(document.text, """
        # top comment
        [app]
        # about the key
        launch_at_login = true   # trailing

        [defaults]
        autorestart_on_crash = false
        """)
    }

    func testAQuotedTableNameIsMatchedByItsUnquotedPath() {
        var document = TOMLDocument("""
        [presets."My Config"]
        kanata_config = "/tmp/a.kbd"
        """)
        XCTAssertTrue(document.hasTable(["presets", "My Config"]))
        document.set(.bool(true), forKey: "autorun", inTable: ["presets", "My Config"])
        XCTAssertTrue(document.text.contains("autorun = true"))
    }

    func testCreatingATableAppendsWhenThereIsNoFamily() {
        var document = TOMLDocument("""
        [app]
        show_dock_icon = false
        """)
        document.createTable(["presets", "New"], body: ["kanata_config = \"/tmp/a.kbd\""], render: ConfigWriter.renderPath)

        XCTAssertEqual(document.text, """
        [app]
        show_dock_icon = false

        [presets."New"]
        kanata_config = "/tmp/a.kbd"
        """)
    }

    func testANewSubTableLandsUnderItsParentRatherThanAtTheEnd() {
        var document = TOMLDocument("""
        [presets."A"]
        kanata_config = "/tmp/a.kbd"

        [presets."B"]
        kanata_config = "/tmp/b.kbd"
        """)
        document.createTable(["presets", "A", "layer_icons"], body: ["base = \"command\""], render: ConfigWriter.renderPath)

        XCTAssertEqual(document.text, """
        [presets."A"]
        kanata_config = "/tmp/a.kbd"

        [presets."A".layer_icons]
        base = "command"

        [presets."B"]
        kanata_config = "/tmp/b.kbd"
        """)
    }

    func testRemovingATableTakesItsSubTablesWithIt() {
        var document = TOMLDocument("""
        [app]
        show_dock_icon = false

        [presets."A"]
        kanata_config = "/tmp/a.kbd"

        [presets."A".layer_icons]
        base = "command"

        [presets."B"]
        kanata_config = "/tmp/b.kbd"
        """)
        document.removeTable(at: ["presets", "A"])

        XCTAssertEqual(document.text, """
        [app]
        show_dock_icon = false

        [presets."B"]
        kanata_config = "/tmp/b.kbd"
        """)
    }

    func testRemovingTheLastTableDoesNotLeaveTrailingBlankLines() {
        var document = TOMLDocument("""
        [app]
        show_dock_icon = false

        [presets."A"]
        kanata_config = "/tmp/a.kbd"
        """)
        document.removeTable(at: ["presets", "A"])

        XCTAssertEqual(document.text, "[app]\nshow_dock_icon = false")
    }

    func testRenamingATableRenamesItsSubTablesToo() {
        var document = TOMLDocument("""
        [presets."A"]  # keep me
        kanata_config = "/tmp/a.kbd"

        [presets."A".layer_icons]
        base = "command"
        """)
        document.renameTable(at: ["presets", "A"], to: ["presets", "Home Row"], render: ConfigWriter.renderPath)

        XCTAssertEqual(document.text, """
        [presets."Home Row"]  # keep me
        kanata_config = "/tmp/a.kbd"

        [presets."Home Row".layer_icons]
        base = "command"
        """)
    }

    func testChildTableNamesFollowFileOrder() {
        let document = TOMLDocument("""
        [presets."Zed"]
        kanata_config = "/tmp/z.kbd"

        [presets."Alpha"]
        kanata_config = "/tmp/a.kbd"
        """)
        XCTAssertEqual(document.childTableNames(of: ["presets"]), ["Zed", "Alpha"])
    }

    func testEditsSurviveARoundTripThroughTheParser() throws {
        var document = TOMLDocument(fullConfigExample)
        ConfigWriter.addPreset("Second", configPath: "/tmp/b.kbd", to: &document)
        ConfigWriter.renamePreset("Default", to: "Primary", in: &document)

        let config = try parseConfig(document.text)
        XCTAssertEqual(config.presets.map(\.name), ["Primary", "Second"])
        XCTAssertEqual(config.preset(named: "Primary")?.autorun, true)
    }
}

final class TOMLEncodeTests: XCTestCase {
    func testBareKeysStayBareAndEverythingElseIsQuoted() {
        XCTAssertEqual(TOMLEncode.key("base"), "base")
        XCTAssertEqual(TOMLEncode.key("layer-2_a"), "layer-2_a")
        XCTAssertEqual(TOMLEncode.key("*"), "\"*\"")
        XCTAssertEqual(TOMLEncode.key("My Config"), "\"My Config\"")
        XCTAssertEqual(TOMLEncode.key(""), "\"\"")
    }

    func testQuotesAndBackslashesInAValueAreEscaped() {
        XCTAssertEqual(TOMLEncode.string(#"a"b\c"#), #""a\"b\\c""#)
        XCTAssertEqual(TOMLEncode.string("a\nb"), #""a\nb""#)
    }

    func testAPathWithAQuotedSegmentRoundTripsThroughTheScanner() {
        let rendered = "[\(TOMLEncode.path(["presets", #"He said "hi""#]))]"
        XCTAssertEqual(TOMLHeaderScanner.keyPath(in: rendered), ["presets", #"He said "hi""#])
    }
}
