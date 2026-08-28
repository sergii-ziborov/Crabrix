import XCTest
@testable import Crabrix

final class RustSourcePatchTests: XCTestCase {
    func testAppliesMultipleEditsUsingOriginalLineNumbers() throws {
        let source = """
        fn main() {
            let value = 1;
            println!("{value}");
        }
        """
        let edits = [
            RustSourceEdit(
                startLine: 2,
                endLine: 2,
                replacement: "    let value = 2;"
            ),
            RustSourceEdit(
                startLine: 3,
                endLine: 3,
                replacement: "    println!(\"value = {value}\");"
            ),
        ]

        let result = try RustSourcePatch.applying(edits, to: source)

        XCTAssertEqual(
            result,
            """
            fn main() {
                let value = 2;
                println!("value = {value}");
            }
            """
        )
    }

    func testRejectsOverlappingEdits() {
        let edits = [
            RustSourceEdit(startLine: 1, endLine: 2, replacement: "first"),
            RustSourceEdit(startLine: 2, endLine: 2, replacement: "second"),
        ]

        XCTAssertThrowsError(try RustSourcePatch.applying(edits, to: "one\ntwo")) { error in
            XCTAssertEqual(error as? RustSourcePatch.PatchError, .overlappingEdits)
        }
    }

    func testRejectsLineOutsideOriginalSnapshot() {
        let edits = [
            RustSourceEdit(startLine: 3, endLine: 3, replacement: "missing"),
        ]

        XCTAssertThrowsError(try RustSourcePatch.applying(edits, to: "one\ntwo")) { error in
            XCTAssertEqual(error as? RustSourcePatch.PatchError, .invalidRange(3, 3))
        }
    }

    func testRemovesMarkdownFenceFromGeneratedReplacement() throws {
        let edit = RustSourceEdit(
            startLine: 1,
            endLine: 1,
            replacement: """
            ```rust
            let value = 2;
            ```
            """
        )

        let result = try RustSourcePatch.applying([edit], to: "let value = 1;")

        XCTAssertEqual(result, "let value = 2;")
    }
}
