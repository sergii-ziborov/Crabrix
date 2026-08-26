import XCTest
@testable import Crabrix

final class SyntaxHighlighterTests: XCTestCase {
    func testHighlightsRustWithoutColoringKeywordsInsideStringsOrComments() {
        let source = """
        // let comment
        fn main() {
            let value: Vec<i32> = vec![42];
            println!("let {value:?}");
        }
        """

        let tokens = SyntaxHighlighter.tokens(in: source, filePath: "src/main.rs")
        let nsSource = source as NSString
        let keywords = tokens.filter { $0.kind == .keyword }.map { nsSource.substring(with: $0.range) }
        let macros = tokens.filter { $0.kind == .macro }.map { nsSource.substring(with: $0.range) }

        XCTAssertEqual(keywords, ["fn", "let"])
        XCTAssertEqual(macros, ["vec!", "println!"])
        XCTAssertTrue(tokens.contains { $0.kind == .comment })
        XCTAssertTrue(tokens.contains { $0.kind == .string })
        XCTAssertTrue(tokens.contains { $0.kind == .type })
        XCTAssertTrue(tokens.contains { $0.kind == .number })
    }

    func testHighlightsCargoManifestSectionsAndKeys() {
        let source = """
        [package]
        name = "crabrix"
        edition = "2024"
        """
        let tokens = SyntaxHighlighter.tokens(in: source, filePath: "Cargo.toml")
        XCTAssertEqual(tokens.filter { $0.kind == .section }.count, 1)
        XCTAssertEqual(tokens.filter { $0.kind == .key }.count, 2)
        XCTAssertEqual(tokens.filter { $0.kind == .string }.count, 2)
    }
}
