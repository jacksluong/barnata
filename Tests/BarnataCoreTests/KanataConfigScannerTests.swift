import Foundation
import XCTest

@testable import BarnataCore

final class KanataConfigScannerTests: XCTestCase {
    func testLayersComeOutInFileOrder() {
        let layers = KanataConfigScanner.layers(in: """
        (defsrc a b c)
        (deflayer base 1 2 3)
        (deflayer typing 4 5 6)
        (deflayer arrows 7 8 9)
        """)
        XCTAssertEqual(layers, ["base", "typing", "arrows"])
    }

    func testDeflayermapNamesAreFoundThroughTheirParentheses() {
        let layers = KanataConfigScanner.layers(in: """
        (deflayermap (numbers) a 1 b 2)
        (deflayer base 1)
        """)
        XCTAssertEqual(layers, ["numbers", "base"])
    }

    func testCommentedOutLayersAreNotCounted() {
        let layers = KanataConfigScanner.layers(in: """
        ;; (deflayer commented 1)
        (deflayer base 1)
        #|
        (deflayer blocked 1)
        |#
        (deflayer real 2)
        """)
        XCTAssertEqual(layers, ["base", "real"])
    }

    func testTheWordDeflayerInsideAStringOrDeeperIsIgnored() {
        let layers = KanataConfigScanner.layers(in: """
        (defalias x (macro "deflayer notalayer"))
        (defcfg process-unmapped-keys yes)
        (deflayer base 1)
        """)
        XCTAssertEqual(layers, ["base"])
    }

    func testDuplicateNamesAppearOnce() {
        XCTAssertEqual(
            KanataConfigScanner.layers(in: "(deflayer base 1)\n(deflayer base 2)"),
            ["base"]
        )
    }

    func testAFileWithNoLayersYieldsNothing() {
        XCTAssertEqual(KanataConfigScanner.layers(in: "(defsrc a)\n"), [])
    }

    func testIncludedFilesContributeTheirLayers() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "(deflayer base 1)\n(include \"layers/extra.kbd\")".write(
            to: root.appending(path: "main.kbd"), atomically: true, encoding: .utf8
        )
        try FileManager.default.createDirectory(at: root.appending(path: "layers"), withIntermediateDirectories: true)
        try "(deflayer extra 1)".write(
            to: root.appending(path: "layers/extra.kbd"), atomically: true, encoding: .utf8
        )

        XCTAssertEqual(KanataConfigScanner.layers(in: root.appending(path: "main.kbd")), ["base", "extra"])
    }

    func testAnIncludeCycleTerminates() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "(deflayer a 1)\n(include \"b.kbd\")".write(to: root.appending(path: "a.kbd"), atomically: true, encoding: .utf8)
        try "(deflayer b 1)\n(include \"a.kbd\")".write(to: root.appending(path: "b.kbd"), atomically: true, encoding: .utf8)

        XCTAssertEqual(KanataConfigScanner.layers(in: root.appending(path: "a.kbd")), ["a", "b"])
    }

    func testAnUnreadableFileYieldsNothingRatherThanThrowing() {
        XCTAssertEqual(KanataConfigScanner.layers(in: URL(fileURLWithPath: "/nope/missing.kbd")), [])
    }
}
