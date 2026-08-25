import XCTest
@testable import Crabrix

final class BorrowRepairTests: XCTestCase {
    func testMovesLastReferenceUseBeforeMutation() {
        let diagnostic = RustDiagnostic(
            level: "error",
            message: "borrow conflict",
            code: "E0502",
            rendered: "borrow conflict",
            spans: [
                .init(
                    lineStart: 4,
                    lineEnd: 4,
                    columnStart: 5,
                    columnEnd: 27,
                    isPrimary: true,
                    label: "mutable borrow occurs here",
                    sourceLine: "    items.push(\"compiler\");"
                ),
                .init(
                    lineStart: 5,
                    lineEnd: 5,
                    columnStart: 16,
                    columnEnd: 21,
                    isPrimary: false,
                    label: "immutable borrow later used here",
                    sourceLine: "    println!(\"{first}\");"
                ),
            ]
        )

        let repaired = BorrowRepair.apply(to: RustSamples.broken, diagnostic: diagnostic)

        XCTAssertNotNil(repaired)
        XCTAssertTrue(repaired?.contains("println!(\"{first}\");\n    items.push") == true)
    }
}
