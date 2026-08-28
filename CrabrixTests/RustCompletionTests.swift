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

final class RustDeclarationCompletionTests: XCTestCase {
    private func insertion(after prefix: String) -> String? {
        RustLocalCompleter.suggestion(for: prefix)?.insertion
    }

    func testCompletesADescriptivelyNamedFunction() {
        // The case that used to fall through to a model that most devices
        // cannot run: `fn` plus a name the user chose.
        XCTAssertEqual(insertion(after: "fn calculate_total"), "() -> usize {\n    0\n}")
        XCTAssertEqual(insertion(after: "fn is_ready"), "() -> bool {\n    false\n}")
        XCTAssertEqual(insertion(after: "fn describe_order"), "() -> String {\n    String::new()\n}")
        XCTAssertEqual(insertion(after: "    fn new"), "() -> Self {\n    Self {}\n}")
        XCTAssertEqual(insertion(after: "fn run_server"), "() {\n    \n}")
    }

    func testHandlesVisibilityAndAsyncModifiers() {
        XCTAssertEqual(insertion(after: "pub fn has_items"), "() -> bool {\n    false\n}")
        XCTAssertEqual(insertion(after: "    pub async fn fetch_orders"), "() {\n    \n}")
    }

    func testCompletesTypeDeclarations() {
        XCTAssertEqual(insertion(after: "struct Order"), " {\n    \n}")
        XCTAssertEqual(insertion(after: "enum PaymentState"), " {\n    \n}")
        XCTAssertEqual(insertion(after: "impl Order"), " {\n    \n}")
    }

    func testBareKeywordWithATrailingSpaceStillUsesTheDefaultTemplate() {
        // A trailing space means no name has been typed yet, so the old
        // deterministic templates are still the right answer.
        XCTAssertEqual(insertion(after: "fn "), "main() {\n    \n}")
        XCTAssertEqual(insertion(after: "let mut "), "items = Vec::new();")
        XCTAssertEqual(insertion(after: "match "), "value {\n    Some(value) => value,\n    None => return,\n}")
        XCTAssertEqual(insertion(after: "for "), "item in items.iter() {\n    println!(\"{item:?}\");\n}")
    }

    func testDoesNotScaffoldAnUnfinishedOrNonDeclarationLine() {
        XCTAssertNil(insertion(after: "fn calculate_total("))
        XCTAssertNil(insertion(after: "let total"))
        XCTAssertNil(insertion(after: "fn Vec<"))
    }

    func testEveryFunctionScaffoldIsBalanced() {
        for name in ["is_open", "new", "count_items", "title", "process"] {
            let value = insertion(after: "fn \(name)")
            let code = try? XCTUnwrap(value)
            XCTAssertEqual(
                code?.filter { $0 == "{" }.count,
                code?.filter { $0 == "}" }.count,
                "\(name) produced unbalanced braces"
            )
            XCTAssertTrue(code?.hasPrefix("()") ?? false, "\(name) should start the parameter list")
        }
    }
}
