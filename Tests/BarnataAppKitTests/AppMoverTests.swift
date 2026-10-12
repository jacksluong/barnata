import Foundation
import XCTest

@testable import BarnataAppKit

final class AppMoverTests: XCTestCase {
    func testTheApplicationsCopyStaysWhereItIs() {
        XCTAssertFalse(AppMover.needsMove(bundle: URL(fileURLWithPath: "/Applications/Barnata.app")))
    }

    func testATranslocatedCopyIsMoved() {
        XCTAssertTrue(AppMover.needsMove(bundle: URL(
            fileURLWithPath: "/private/var/folders/xy/T/AppTranslocation/0A1B2C3D/d/Barnata.app")))
    }

    func testADownloadsCopyIsMoved() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads/Barnata.app")
        XCTAssertTrue(AppMover.needsMove(bundle: downloads))
    }

    func testACopyOnTheMountedDMGIsMoved() {
        XCTAssertTrue(AppMover.needsMove(bundle: URL(fileURLWithPath: "/Volumes/Barnata/Barnata.app")))
    }
}
