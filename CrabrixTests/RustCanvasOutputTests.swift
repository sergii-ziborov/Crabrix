import XCTest
@testable import Crabrix

final class RustCanvasOutputTests: XCTestCase {
    func testValidCanvasIsSeparatedFromPlainOutput() throws {
        let output = """
        CRABRIX_CANVAS:{"title":"Tiny","width":2,"height":2,"palette":["#000000","#FFFFFF"],"pixels":"0110"}
        built locally
        """

        let parsed = RustCanvasOutput.parse(output)
        let frame = try XCTUnwrap(parsed.frame)

        XCTAssertEqual(frame.title, "Tiny")
        XCTAssertEqual(frame.width, 2)
        XCTAssertEqual(frame.height, 2)
        XCTAssertEqual(frame.palette, ["#000000", "#FFFFFF"])
        XCTAssertEqual(frame.pixels, [0, 1, 1, 0])
        XCTAssertEqual(parsed.plainText, "built locally")
    }

    func testInvalidCanvasRemainsVisibleAsPlainOutput() {
        let invalid = """
        CRABRIX_CANVAS:{"width":65,"height":1,"palette":["#000000"],"pixels":"0"}
        """

        let parsed = RustCanvasOutput.parse(invalid)

        XCTAssertNil(parsed.frame)
        XCTAssertEqual(parsed.plainText, invalid)
    }

    func testRejectsUnknownPaletteIndexAndMalformedColor() {
        let unknownIndex = "CRABRIX_CANVAS:{\"width\":1,\"height\":1,\"palette\":[\"#000000\"],\"pixels\":\"f\"}"
        let badColor = "CRABRIX_CANVAS:{\"width\":1,\"height\":1,\"palette\":[\"black\"],\"pixels\":\"0\"}"

        XCTAssertNil(RustCanvasOutput.parse(unknownIndex).frame)
        XCTAssertNil(RustCanvasOutput.parse(badColor).frame)
    }
}
