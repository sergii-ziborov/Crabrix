import XCTest
@testable import Crabrix

final class RustDiagnosticParserTests: XCTestCase {
    func testParsesStructuredE0502AndSpans() throws {
        let json = #"{"$message_type":"diagnostic","message":"cannot borrow `items` as mutable because it is also borrowed as immutable","code":{"code":"E0502"},"level":"error","spans":[{"file_name":"/work/main.rs","line_start":4,"line_end":4,"column_start":5,"column_end":27,"is_primary":true,"text":[{"text":"    items.push(\"compiler\");"}],"label":"mutable borrow occurs here"},{"file_name":"/work/main.rs","line_start":3,"line_end":3,"column_start":18,"column_end":23,"is_primary":false,"text":[{"text":"    let first = &items[0];"}],"label":"immutable borrow occurs here"},{"file_name":"/work/main.rs","line_start":5,"line_end":5,"column_start":16,"column_end":21,"is_primary":false,"text":[{"text":"    println!(\"{first}\");"}],"label":"immutable borrow later used here"}],"rendered":"error[E0502]: borrow conflict"}"#

        let diagnostics = RustDiagnosticParser.parse(stderr: json)

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].code, "E0502")
        XCTAssertEqual(diagnostics[0].primarySpan?.fileName, "main.rs")
        XCTAssertEqual(diagnostics[0].primarySpan?.lineStart, 4)
        XCTAssertEqual(diagnostics[0].spans.count, 3)
    }

    func testKeepsSupportingFilePathForEditorNavigation() throws {
        let json = #"{"$message_type":"diagnostic","message":"missing item","code":{"code":"E0425"},"level":"error","spans":[{"file_name":"/work/src/greeter.rs","line_start":7,"line_end":7,"column_start":9,"column_end":16,"is_primary":true,"text":[{"text":"missing();"}],"label":"not found"}],"rendered":"error[E0425]"}"#

        let diagnostic = try XCTUnwrap(RustDiagnosticParser.parse(stderr: json).first)

        XCTAssertEqual(diagnostic.primarySpan?.fileName, "src/greeter.rs")
        XCTAssertEqual(diagnostic.primarySpan?.lineStart, 7)
    }

    func testIgnoresSummaryDiagnosticsWithoutSeverity() {
        let stderr = #"{"$message_type":"diagnostic","message":"aborting due to 1 previous error","code":null,"level":"error","spans":[],"rendered":"aborting"}"#

        let diagnostics = RustDiagnosticParser.parse(stderr: stderr)

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertNil(diagnostics[0].code)
        XCTAssertTrue(diagnostics[0].spans.isEmpty)
    }
}
