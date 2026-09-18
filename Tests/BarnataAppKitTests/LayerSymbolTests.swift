import XCTest

@testable import BarnataAppKit

final class LayerSymbolTests: XCTestCase {
    func testASymbolOutsideTheCatalogIsStillValid() {
        XCTAssertTrue(LayerSymbol.isAvailable("house.fill"))
        XCTAssertTrue(LayerSymbol.isAvailable("arrow.up.and.down.and.arrow.left.and.right"))
    }

    func testNamesThisMacCannotDrawAreRejected() {
        XCTAssertFalse(LayerSymbol.isAvailable("baseTemplate.png"))
        XCTAssertFalse(LayerSymbol.isAvailable("not.a.symbol"))
        XCTAssertFalse(LayerSymbol.isAvailable(""))
    }

    func testEveryLayerWithAnUndrawableIconIsReported() {
        let icons = ["base": "house.fill", "typing": "typingTemplate.png", "*": "not.a.symbol"]
        XCTAssertEqual(LayerSymbol.unavailable(in: icons), ["*", "typing"])
    }
}
