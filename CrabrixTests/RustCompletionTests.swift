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
}
