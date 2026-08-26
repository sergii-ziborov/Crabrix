import XCTest
@testable import Crabrix

final class RustCompletionTests: XCTestCase {
    func testCompletesPrintlnPrefixWithoutUsingAModel() {
        let suggestion = RustLocalCompleter.suggestion(
            for: "fn main() {\n    pri"
        )

        XCTAssertEqual(suggestion?.provider, .local)
        XCTAssertEqual(suggestion?.insertion, "ntln!(\"Hello, Crabrix!\");")
    }

    func testDoesNotInventCompletionWithoutKnownRustContext() {
        XCTAssertNil(RustLocalCompleter.suggestion(for: "fn main() {\n    value"))
    }

    func testCompletesCommonRustConstructsFromTwoCharacters() {
        XCTAssertEqual(
            RustLocalCompleter.suggestion(for: "fn main() {\n    mat")?.insertion,
            "ch value {\n    Some(value) => value,\n    None => return,\n}"
        )
        XCTAssertEqual(
            RustLocalCompleter.suggestion(for: "fn main() {\n    Vec")?.insertion,
            "::new()"
        )
        XCTAssertEqual(
            RustLocalCompleter.suggestion(for: "fn main() {\n    items.it")?.insertion,
            "er()"
        )
    }
}
