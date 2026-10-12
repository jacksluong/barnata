import Foundation
import XCTest

@testable import BarnataAppKit

final class UninstallerTests: XCTestCase {
    func testTheCaskroomFolderIsDeletedWhenPresent() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "barnata-caskroom-\(UUID().uuidString)/barnata")
        try FileManager.default.createDirectory(at: folder.appending(path: "0.5.0"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

        XCTAssertEqual(Uninstaller.removeCaskroomRecords([folder]), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testAMissingCaskroomFolderIsNotAnError() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "barnata-missing-\(UUID().uuidString)")
        XCTAssertEqual(Uninstaller.removeCaskroomRecords([folder]), [])
    }
}
