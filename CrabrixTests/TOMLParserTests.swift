import XCTest
@testable import Crabrix

final class TOMLParserTests: XCTestCase {
    func testParsesTablesDottedKeysAndInlineTables() throws {
        let document = try TOMLParser.parse("""
        # a comment
        title = "crabrix"
        answer = 42
        ratio = 1.5
        enabled = true

        [package]
        name = "demo"
        version = "0.1.0"

        [package.metadata]
        docs.rs.features = ["a", "b"]

        [dependencies]
        anyhow = "1"
        serde = { version = "1.0", features = ["derive"], default-features = false }
        """)

        XCTAssertEqual(document["title"]?.stringValue, "crabrix")
        XCTAssertEqual(document["answer"]?.integerValue, 42)
        XCTAssertEqual(document["enabled"]?.boolValue, true)
        XCTAssertEqual(document["package"]?["name"]?.stringValue, "demo")
        XCTAssertEqual(
            document["package"]?["metadata"]?["docs"]?["rs"]?["features"]?.stringArrayValue,
            ["a", "b"]
        )
        XCTAssertEqual(document["dependencies"]?["anyhow"]?.stringValue, "1")
        let serde = try XCTUnwrap(document["dependencies"]?["serde"]?.tableValue)
        XCTAssertEqual(serde["version"]?.stringValue, "1.0")
        XCTAssertEqual(serde["features"]?.stringArrayValue, ["derive"])
        XCTAssertEqual(serde["default-features"]?.boolValue, false)
    }

    func testParsesArraysOfTablesAndMultiLineArrays() throws {
        let document = try TOMLParser.parse("""
        [[bin]]
        name = "one"
        path = "src/one.rs"

        [[bin]]
        name = "two"

        # Keys after an array-of-tables header belong to its newest element.
        keywords = [
            "rust",   # trailing comment
            "ios",
        ]
        """)

        let bins = try XCTUnwrap(document["bin"]?.arrayValue)
        XCTAssertEqual(bins.count, 2)
        XCTAssertEqual(bins[0]["name"]?.stringValue, "one")
        XCTAssertEqual(bins[0]["path"]?.stringValue, "src/one.rs")
        XCTAssertEqual(bins[1]["name"]?.stringValue, "two")
        XCTAssertEqual(bins[1]["keywords"]?.stringArrayValue, ["rust", "ios"])
    }

    func testParsesQuotedKeysAndStringForms() throws {
        let document = try TOMLParser.parse(#"""
        [target."cfg(any(unix, windows))".dependencies]
        libc = "0.2"

        [text]
        literal = 'C:\Users\raw'
        escaped = "line\nbreak\tend"
        block = """
        first
        second"""
        """#)

        XCTAssertEqual(
            document["target"]?["cfg(any(unix, windows))"]?["dependencies"]?["libc"]?.stringValue,
            "0.2"
        )
        XCTAssertEqual(document["text"]?["literal"]?.stringValue, #"C:\Users\raw"#)
        XCTAssertEqual(document["text"]?["escaped"]?.stringValue, "line\nbreak\tend")
        XCTAssertEqual(document["text"]?["block"]?.stringValue, "first\nsecond")
    }

    func testRejectsOversizedInput() {
        let huge = String(repeating: "a", count: TOMLParser.maximumInputBytes + 1)
        XCTAssertThrowsError(try TOMLParser.parse(huge)) { error in
            XCTAssertEqual(error as? TOMLParseError, .tooLarge)
        }
    }

    func testRejectsDuplicateKeys() {
        XCTAssertThrowsError(try TOMLParser.parse("a = 1\na = 2"))
    }
}
