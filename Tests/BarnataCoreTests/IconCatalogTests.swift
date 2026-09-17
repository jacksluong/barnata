import Foundation
import XCTest

@testable import BarnataCore

final class IconCatalogTests: XCTestCase {
    func testTheCatalogHasNoDuplicatesAndNoEmptyGroups() {
        XCTAssertEqual(Set(IconCatalog.symbols).count, IconCatalog.symbols.count)
        for group in IconCatalog.groups {
            XCTAssertFalse(group.symbols.isEmpty, group.name)
        }
    }

    func testTheWarningSymbolIsTheOneTheMenuBarAlreadyUses() {
        XCTAssertEqual(IconCatalog.warningSymbol, "exclamationmark.triangle.fill")
        XCTAssertTrue(IconCatalog.contains(IconCatalog.warningSymbol))
    }

    func testOnlyCatalogSymbolsAreAllowed() {
        XCTAssertTrue(IconCatalog.contains("command"))
        XCTAssertFalse(IconCatalog.contains("baseTemplate.png"))
        XCTAssertFalse(IconCatalog.contains(""))
        XCTAssertFalse(IconCatalog.contains("Command"))
    }

    func testAPresetReportsEveryLayerWhoseIconIsNotInThePool() {
        let preset = Preset(
            name: "P",
            configPaths: ["/tmp/a.kbd"],
            layerIcons: ["base": "command", "typing": "typingTemplate.png", "*": "not.a.symbol"]
        )
        XCTAssertEqual(preset.invalidLayerIcons, ["*", "typing"])
    }

    func testAPresetWithOnlyCatalogIconsReportsNothing() {
        let preset = Preset(name: "P", configPaths: ["/tmp/a.kbd"], layerIcons: ["base": "command", "*": "circle"])
        XCTAssertEqual(preset.invalidLayerIcons, [])
    }

    func testTheFallbackStillAnswersForUnknownLayers() {
        let preset = Preset(name: "P", configPaths: ["/tmp/a.kbd"], layerIcons: ["base": "command", "*": "circle"])
        XCTAssertEqual(preset.iconSymbol(forLayer: "base"), "command")
        XCTAssertEqual(preset.iconSymbol(forLayer: "whatever"), "circle")
    }
}
