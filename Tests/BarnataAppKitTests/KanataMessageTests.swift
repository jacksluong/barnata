import Foundation
import XCTest

@testable import BarnataAppKit

final class KanataClientMessageTests: XCTestCase {
    func testTheLinesMatchTheProtocolInTheArchitectureDoc() {
        XCTAssertEqual(KanataClientMessage.hello.line, "{\"Hello\":{}}")
        XCTAssertEqual(KanataClientMessage.requestLayerNames.line, "{\"RequestLayerNames\":{}}")
        XCTAssertEqual(KanataClientMessage.requestCurrentLayerName.line, "{\"RequestCurrentLayerName\":{}}")
        XCTAssertEqual(KanataClientMessage.changeLayer("base").line, "{\"ChangeLayer\":{\"new\":\"base\"}}")
        XCTAssertEqual(KanataClientMessage.reload.line, "{\"Reload\":{}}")
        XCTAssertEqual(KanataClientMessage.reloadNext.line, "{\"ReloadNext\":{}}")
        XCTAssertEqual(KanataClientMessage.reloadPrevious.line, "{\"ReloadPrev\":{}}")
    }

    func testALayerNameWithAQuoteIsEscaped() {
        XCTAssertEqual(
            KanataClientMessage.changeLayer("a\"b").line,
            "{\"ChangeLayer\":{\"new\":\"a\\\"b\"}}"
        )
    }

    func testEveryLineIsValidJSON() throws {
        let messages: [KanataClientMessage] = [
            .hello, .requestLayerNames, .requestCurrentLayerName,
            .changeLayer("a\"b\\c"), .reload, .reloadNext, .reloadPrevious,
        ]
        for message in messages {
            let data = Data(message.line.utf8)
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data), message.line)
        }
    }
}

final class KanataServerMessageTests: XCTestCase {
    func testDecodesTheHandledMessages() {
        XCTAssertEqual(KanataServerMessage.decode(line: "{\"LayerChange\":{\"new\":\"arrows\"}}"), .layerChange("arrows"))
        XCTAssertEqual(
            KanataServerMessage.decode(line: "{\"LayerNames\":{\"names\":[\"base\",\"typing\"]}}"),
            .layerNames(["base", "typing"])
        )
        XCTAssertEqual(
            KanataServerMessage.decode(line: "{\"CurrentLayerName\":{\"name\":\"base\"}}"),
            .currentLayerName("base")
        )
        XCTAssertEqual(KanataServerMessage.decode(line: "{\"ConfigFileReload\":{}}"), .configFileReload)
        XCTAssertEqual(KanataServerMessage.decode(line: "{\"Error\":{\"msg\":\"boom\"}}"), .error("boom"))
    }

    func testReloadResultCarriesSuccessAndMessage() {
        XCTAssertEqual(
            KanataServerMessage.decode(line: "{\"ReloadResult\":{\"success\":false,\"msg\":\"line 4\"}}"),
            .reloadResult(ok: false, message: "line 4")
        )
        XCTAssertEqual(
            KanataServerMessage.decode(line: "{\"ReloadResult\":{\"status\":\"Success\"}}"),
            .reloadResult(ok: true, message: nil)
        )
    }

    func testUnhandledAndMalformedLinesAreIgnoredRatherThanFatal() {
        XCTAssertEqual(KanataServerMessage.decode(line: "{\"HoldActivated\":{}}"), .ignored("HoldActivated"))
        XCTAssertEqual(KanataServerMessage.decode(line: "not json"), .ignored("not json"))
        XCTAssertNil(KanataServerMessage.decode(line: "   "))
    }

    func testTheInvalidMessageComplaintIsRecognized() {
        let message = KanataServerMessage.decode(line: "{\"Error\":{\"msg\":\"you sent an invalid message\"}}")
        XCTAssertEqual(message?.isInvalidMessageComplaint, true)
        XCTAssertEqual(KanataServerMessage.error("boom").isInvalidMessageComplaint, false)
    }
}
