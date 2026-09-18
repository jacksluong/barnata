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
        XCTAssertTrue(IconCatalog.isCurated(IconCatalog.warningSymbol))
    }

    func testTheCatalogKnowsWhatItOffers() {
        XCTAssertTrue(IconCatalog.isCurated("command"))
        XCTAssertTrue(IconCatalog.isCurated("house.fill"))
        XCTAssertFalse(IconCatalog.isCurated("baseTemplate.png"))
        XCTAssertFalse(IconCatalog.isCurated(""))
        XCTAssertFalse(IconCatalog.isCurated("Command"))
    }

    func testTheFallbackStillAnswersForUnknownLayers() {
        let preset = Preset(name: "P", configPaths: ["/tmp/a.kbd"], layerIcons: ["base": "command", "*": "circle"])
        XCTAssertEqual(preset.iconSymbol(forLayer: "base"), "command")
        XCTAssertEqual(preset.iconSymbol(forLayer: "whatever"), "circle")
    }
}
