import XCTest
import SwiftUI
import UIKit
@testable import Crabrix

final class RustSmartNewlineTests: XCTestCase {
    func testEnterAfterOpeningBraceAddsIndentedBodyAndClosingBrace() throws {
        let source = "    if ready {"
        let edit = try XCTUnwrap(RustSmartNewline.plan(
            in: source,
            range: NSRange(location: (source as NSString).length, length: 0),
            filePath: "src/main.rs"
        ))
        XCTAssertEqual(edit.replacement, "\n        \n    }")
        XCTAssertEqual(edit.cursorOffset, ("\n        " as NSString).length)
    }

    func testEnterBetweenExistingBracesDoesNotAddAnotherCloser() throws {
        let source = "fn main() {}"
        let cursor = (source as NSString).range(of: "{").location + 1
        let edit = try XCTUnwrap(RustSmartNewline.plan(
            in: source,
            range: NSRange(location: cursor, length: 0),
            filePath: "main.rs"
        ))
        XCTAssertEqual(edit.replacement, "\n    \n")
        XCTAssertEqual(edit.cursorOffset, 5)
    }

    func testEnterKeepsCurrentBlockIndentOnOrdinaryLine() throws {
        let source = "fn main() {\n    let answer = 42;"
        let edit = try XCTUnwrap(RustSmartNewline.plan(
            in: source,
            range: NSRange(location: (source as NSString).length, length: 0),
            filePath: "src/main.rs"
        ))
        XCTAssertEqual(edit.replacement, "\n    ")
    }

    func testEnterDoesNotCloseBraceInsideCommentOrTextFile() throws {
        let source = "    // {"
        let cursor = (source as NSString).length
        XCTAssertEqual(
            RustSmartNewline.plan(in: source,
                                  range: NSRange(location: cursor, length: 0),
                                  filePath: "main.rs")?.replacement,
            "\n    "
        )
        XCTAssertNil(RustSmartNewline.plan(
            in: source,
            range: NSRange(location: cursor, length: 0),
            filePath: "Cargo.toml"
        ))
    }
}

@MainActor
final class SyntaxCodeEditorHostedTests: XCTestCase {
    private final class Box: ObservableObject {
        @Published var text = "fn main() {}"
        @Published var cursor = 0
    }

    private struct Host: View {
        @ObservedObject var box: Box
        var body: some View {
            SyntaxCodeEditor(
                text: $box.text,
                cursorOffset: $box.cursor,
                filePath: "src/main.rs",
                isEditable: true,
                navigationTarget: nil,
                onRequestCompletion: {}
            )
        }
    }

    private func findTextView(_ view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(subview) { return found }
        }
        return nil
    }

    private func findCanvas(_ view: UIView) -> CodeEditorCanvas? {
        if let canvas = view as? CodeEditorCanvas { return canvas }
        for subview in view.subviews {
            if let found = findCanvas(subview) { return found }
        }
        return nil
    }

    func testEnterInRealEditorCreatesRustBlock() throws {
        let box = Box()
        box.text = "fn main() {"
        box.cursor = (box.text as NSString).length
        let controller = UIHostingController(rootView: Host(box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()

        let textView = try XCTUnwrap(findTextView(controller.view))
        let cursor = (textView.text as NSString).length
        textView.selectedRange = NSRange(location: cursor, length: 0)
        let accepted = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: NSRange(location: cursor, length: 0),
            replacementText: "\n"
        )

        XCTAssertEqual(accepted, false)
        XCTAssertEqual(textView.text, "fn main() {\n    \n}")
        XCTAssertEqual(textView.selectedRange.location, 16)
        XCTAssertEqual(box.text, textView.text)
        window.isHidden = true
    }

    func testRealEditorHighlightsTextInsertedThroughUIKit() throws {
        let box = Box()
        let controller = UIHostingController(rootView: Host(box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()

        let textView = try XCTUnwrap(findTextView(controller.view), "no UITextView was created")
        let plain = UIColor(CrabrixTheme.primary)

        func color(of substring: String) throws -> UIColor {
            let range = (textView.text as NSString).range(of: substring)
            XCTAssertNotEqual(range.location, NSNotFound, "\(substring) missing from editor")
            return try XCTUnwrap(
                textView.textStorage.attributes(at: range.location, effectiveRange: nil)[.foregroundColor] as? UIColor
            )
        }

        XCTAssertNotEqual(try color(of: "fn"), plain, "loaded text should be highlighted")

        // The genuine UIKit input path: this updates the storage using
        // typingAttributes and then notifies the delegate.
        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)
        textView.insertText("\nlet answer = 42;")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(box.text, textView.text, "binding must follow UIKit input")
        XCTAssertNotEqual(try color(of: "let"), plain, "typed keyword must be highlighted")
        XCTAssertNotEqual(try color(of: "42"), plain, "typed number must be highlighted")
    }

    func testRealEditorHighlightsProgrammaticallyInsertedText() throws {
        let box = Box()
        let controller = UIHostingController(rootView: Host(box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()

        let textView = try XCTUnwrap(findTextView(controller.view))
        let plain = UIColor(CrabrixTheme.primary)

        // This is what accepting a completion does: it drives the binding.
        box.text = "fn main() {\n    let mut total: u32 = 0;\n}"
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let range = (textView.text as NSString).range(of: "mut")
        XCTAssertNotEqual(range.location, NSNotFound, "editor text did not follow the binding")
        let color = try XCTUnwrap(
            textView.textStorage.attributes(at: range.location, effectiveRange: nil)[.foregroundColor] as? UIColor
        )
        XCTAssertNotEqual(color, plain, "inserted keyword must be highlighted")
    }

    func testHighlightsACargoManifestTypedByTheUser() throws {
        let box = Box()
        box.text = "[package]\nname = \"demo\"\n"
        let controller = UIHostingController(
            rootView: ManifestHost(box: box)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()

        let textView = try XCTUnwrap(findTextView(controller.view))
        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)
        textView.insertText("edition = \"2024\"\n")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let range = (textView.text as NSString).range(of: "edition")
        XCTAssertNotEqual(range.location, NSNotFound)
        let color = try XCTUnwrap(
            textView.textStorage.attributes(at: range.location, effectiveRange: nil)[.foregroundColor] as? UIColor
        )
        XCTAssertNotEqual(color, UIColor(CrabrixTheme.primary), "a manifest key typed by the user must be highlighted")
    }

    private struct ManifestHost: View {
        @ObservedObject var box: Box
        var body: some View {
            SyntaxCodeEditor(
                text: $box.text,
                cursorOffset: $box.cursor,
                filePath: "Cargo.toml",
                isEditable: true,
                navigationTarget: nil,
                onRequestCompletion: {}
            )
        }
    }

    func testLongLinesDoNotWrap() throws {
        let box = Box()
        // One line far wider than the view; it must scroll, not wrap.
        box.text = "let values = vec![" + (0..<60).map(String.init).joined(separator: ", ") + "];"
        let controller = UIHostingController(rootView: Host(box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        controller.view.layoutIfNeeded()

        let canvas = try XCTUnwrap(findCanvas(controller.view))
        let textView = canvas.textView

        var fragments = 0
        let full = NSRange(location: 0, length: textView.textStorage.length)
        let glyphs = textView.layoutManager.glyphRange(forCharacterRange: full, actualCharacterRange: nil)
        textView.layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in
            fragments += 1
        }

        XCTAssertEqual(fragments, 1, "a single long line must stay on one line")
        XCTAssertFalse(
            textView.textContainer.widthTracksTextView,
            "the container must not track the view width, or text wraps"
        )
        XCTAssertGreaterThan(
            textView.bounds.width, canvas.bounds.width,
            "content should be horizontally scrollable"
        )
    }

    func testShortLinesStillLayOutNormally() throws {
        let box = Box()
        box.text = "fn main() {\n    let a = 1;\n}"
        let controller = UIHostingController(rootView: Host(box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let textView = try XCTUnwrap(findTextView(controller.view))
        var fragments = 0
        let full = NSRange(location: 0, length: textView.textStorage.length)
        let glyphs = textView.layoutManager.glyphRange(forCharacterRange: full, actualCharacterRange: nil)
        textView.layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in
            fragments += 1
        }
        XCTAssertEqual(fragments, 3, "three source lines should be three fragments")
    }
}

@MainActor
final class EditorScrollingTests: XCTestCase {
    private final class Box: ObservableObject {
        @Published var text = ""
        @Published var cursor = 0
    }

    private struct Host: View {
        @ObservedObject var box: Box
        var body: some View {
            SyntaxCodeEditor(
                text: $box.text,
                cursorOffset: $box.cursor,
                filePath: "src/main.rs",
                isEditable: true,
                navigationTarget: nil,
                onRequestCompletion: {}
            )
        }
    }

    private func findTextView(_ view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(subview) { return found }
        }
        return nil
    }

    private func findCanvas(_ view: UIView) -> CodeEditorCanvas? {
        if let canvas = view as? CodeEditorCanvas { return canvas }
        for subview in view.subviews {
            if let found = findCanvas(subview) { return found }
        }
        return nil
    }

    /// A file long enough to scroll and wide enough to need sideways scrolling.
    private func makeEditor(lines: Int = 400) throws -> (CodeEditorCanvas, UIWindow) {
        let box = Box()
        box.text = (0..<lines)
            .map { "    let value_\($0) = compute_something_with_a_long_name(\($0), \"argument\");" }
            .joined(separator: "\n")

        // Hosted in a real window: SwiftUI does not build the UIKit view tree
        // for a controller that was never placed in one.
        let controller = UIHostingController(rootView: Host(box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()

        let canvas = try XCTUnwrap(findCanvas(controller.view), "no editor was created")
        canvas.layoutIfNeeded()
        return (canvas, window)
    }

    func testALongFileScrollsPastTheFirstLineAndStaysThere() throws {
        let (canvas, window) = try makeEditor()
        defer { window.isHidden = true }

        XCTAssertGreaterThan(
            canvas.textView.bounds.height, canvas.bounds.height,
            "a 400-line file has to be taller than the viewport to scroll at all"
        )

        canvas.scrollOffset = CGPoint(x: 0, y: 1_200)
        // Several layout passes, which is what scrolling actually causes.
        for _ in 0..<4 { canvas.layoutIfNeeded() }

        XCTAssertEqual(
            canvas.scrollOffset.y, 1_200, accuracy: 1,
            "layout must not drag the reader back to the first line"
        )
    }

    func testHorizontalScrollPositionSurvivesLayout() throws {
        let (canvas, window) = try makeEditor()
        defer { window.isHidden = true }

        XCTAssertGreaterThan(
            canvas.textView.bounds.width, canvas.bounds.width,
            "long lines have to make the content wider than the viewport"
        )

        canvas.scrollOffset = CGPoint(x: 220, y: 600)
        for _ in 0..<4 { canvas.layoutIfNeeded() }

        XCTAssertEqual(canvas.scrollOffset.x, 220, accuracy: 1)
        XCTAssertEqual(canvas.scrollOffset.y, 600, accuracy: 1)
    }

    func testTheGutterStaysOverTheVisibleLeftEdgeWhenScrolledSideways() throws {
        let (canvas, window) = try makeEditor()
        defer { window.isHidden = true }

        canvas.scrollOffset = CGPoint(x: 260, y: 400)
        canvas.layoutIfNeeded()

        // The gutter sits beside the scrolling text rather than inside it, so
        // the code slides underneath and the numbers stay at the left edge.
        let gutter = try XCTUnwrap(
            canvas.subviews.first { String(describing: type(of: $0)).contains("Gutter") }
        )
        XCTAssertEqual(gutter.frame.minX, 0, accuracy: 1, "the gutter must stay at the left edge")
        XCTAssertEqual(gutter.frame.minY, 0, accuracy: 1)
        XCTAssertNotNil(gutter.backgroundColor, "a transparent gutter lets code show through")
        XCTAssertEqual(
            canvas.subviews.last, gutter,
            "the gutter has to stay in front of the text"
        )
    }

    func testTheGutterNumbersFollowTheScrolledLines() throws {
        let (canvas, window) = try makeEditor()
        defer { window.isHidden = true }

        canvas.scrollOffset = CGPoint(x: 0, y: 1_200)
        canvas.layoutIfNeeded()

        let visible = CGRect(origin: canvas.scrollOffset, size: canvas.bounds.size)
        let numbers = canvas.textView.lineNumbers(in: visible).map(\.number)

        XCTAssertFalse(numbers.isEmpty, "the gutter numbered nothing")
        XCTAssertEqual(numbers, numbers.sorted(), "line numbers must run downwards")
        XCTAssertEqual(Set(numbers).count, numbers.count, "each line is numbered once")
        XCTAssertGreaterThan(
            try XCTUnwrap(numbers.first), 40,
            "scrolled well down the file, the top line is not line 1"
        )
    }

    func testTypingWhereTheReaderIsLookingKeepsThemThere() throws {
        let (canvas, window) = try makeEditor()
        defer { window.isHidden = true }
        let textView = canvas.textView

        canvas.scrollOffset = CGPoint(x: 0, y: 900)
        canvas.layoutIfNeeded()

        // The caret goes where the reader is looking, which is what typing in
        // a scrolled file means.
        let line = try XCTUnwrap(
            textView.characterRange(at: CGPoint(x: 80, y: 940))
        )
        textView.selectedTextRange = line
        textView.insertText("// a comment\n")
        canvas.layoutIfNeeded()

        XCTAssertEqual(
            canvas.scrollOffset.y, 900, accuracy: 120,
            "editing where the reader is looking must not move them somewhere else"
        )
    }

    func testTypingPastTheRightEdgeFollowsTheCaret() throws {
        let (canvas, window) = try makeEditor(lines: 3)
        defer { window.isHidden = true }
        let textView = canvas.textView

        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)
        textView.insertText(String(repeating: "x", count: 200))
        canvas.layoutIfNeeded()

        XCTAssertGreaterThan(
            canvas.scrollOffset.x, 0,
            "typing off the right edge has to bring the caret back into view"
        )
    }
}

@MainActor
final class EditorRepaintScrollTests: XCTestCase {
    private final class Box: ObservableObject {
        @Published var text = ""
        @Published var cursor = 0
    }

    private struct Host: View {
        @ObservedObject var box: Box
        var body: some View {
            SyntaxCodeEditor(
                text: $box.text,
                cursorOffset: $box.cursor,
                filePath: "src/main.rs",
                isEditable: true,
                navigationTarget: nil,
                onRequestCompletion: {}
            )
        }
    }

    private func findTextView(_ view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(subview) { return found }
        }
        return nil
    }

    private func findCanvas(_ view: UIView) -> CodeEditorCanvas? {
        if let canvas = view as? CodeEditorCanvas { return canvas }
        for subview in view.subviews {
            if let found = findCanvas(subview) { return found }
        }
        return nil
    }

    func testRepaintingDoesNotDragTheReaderBackToTheFirstLine() throws {
        let box = Box()
        box.text = (0..<500).map { "let value_\($0) = \($0);" }.joined(separator: "\n")

        let controller = UIHostingController(rootView: Host(box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()

        let canvas = try XCTUnwrap(findCanvas(controller.view))
        let textView = canvas.textView
        let coordinator = try XCTUnwrap(textView.delegate as? SyntaxCodeEditor.Coordinator)

        // Caret near the top, reader scrolled well past it — the situation
        // where re-applying the selection is visibly wrong.
        textView.selectedRange = NSRange(location: 0, length: 0)
        canvas.layoutIfNeeded()
        canvas.scrollOffset = CGPoint(x: 0, y: 2_000)
        canvas.layoutIfNeeded()

        // A repaint — theme change, font change, a re-render from anywhere.
        coordinator.applyHighlighting(to: textView, filePath: "src/main.rs")
        canvas.layoutIfNeeded()

        XCTAssertEqual(
            canvas.scrollOffset.y, 2_000, accuracy: 1,
            "re-applying the selection scrolled it into view, yanking the reader to line 1"
        )
    }

}

@MainActor
final class CodeBlockHeightTests: XCTestCase {
    private func measuredHeight(ofLines count: Int) -> CGFloat {
        let code = (0..<count).map { "let value_\($0) = compute(\($0));" }.joined(separator: "\n")
        let controller = UIHostingController(rootView: HighlightedCodeBlock(code: code))
        return controller.sizeThatFits(
            in: CGSize(width: 360, height: UIView.layoutFittingCompressedSize.height)
        ).height
    }

    func testALongSnippetAsksForItsFullHeight() {
        // A block squeezed to its container's height cannot be scrolled past
        // its first screenful, which is what made long code unreadable.
        let short = measuredHeight(ofLines: 4)
        let long = measuredHeight(ofLines: 400)
        XCTAssertGreaterThan(
            long, short * 10,
            "a 400-line snippet must request far more height than a 4-line one"
        )
        XCTAssertGreaterThan(long, 2_000, "400 lines cannot fit in one screen")
    }

    func testHeightGrowsWithTheNumberOfLines() {
        let ten = measuredHeight(ofLines: 10)
        let forty = measuredHeight(ofLines: 40)
        XCTAssertGreaterThan(forty, ten * 3)
    }
}

final class SourceLineEditTests: XCTestCase {
    private let source = "fn main() {\n    let x: i32 = \"a\";\n    println!(\"{x}\");\n}"

    private func span(_ lineStart: Int, to lineEnd: Int? = nil) -> RustDiagnostic.Span {
        RustDiagnostic.Span(
            lineStart: lineStart,
            lineEnd: lineEnd ?? lineStart,
            columnStart: 18,
            columnEnd: 21,
            isPrimary: true,
            label: nil,
            sourceLine: ""
        )
    }

    private func edit(_ old: String, _ new: String) throws -> SourceLineEdit {
        try XCTUnwrap(SourceLineEdit.between(old, new), "the texts differ, so there is an edit")
    }

    func testUnchangedTextIsNoEdit() {
        XCTAssertNil(SourceLineEdit.between(source, source))
    }

    func testTypingOnTheReportedLineDropsItsSpan() throws {
        let edit = try edit(source, source.replacingOccurrences(of: "\"a\";", with: "\"a\".len();"))
        XCTAssertNil(edit.rebase(span(2)), "the line being fixed must lose its marker")
        XCTAssertEqual(edit.rebase(span(1)), span(1))
        XCTAssertEqual(edit.rebase(span(3)), span(3), "a line that did not move keeps its marker")
    }

    func testTypingOnAnotherLineKeepsTheSpan() throws {
        let edit = try edit(source, source.replacingOccurrences(of: "{x}", with: "{x}!"))
        XCTAssertEqual(edit.rebase(span(2)), span(2))
        XCTAssertNil(edit.rebase(span(3)))
    }

    func testALineInsertedAboveMovesTheSpanDown() throws {
        // Return pressed at the end of the first line.
        let edit = try edit(source, source.replacingOccurrences(of: "{\n", with: "{\n\n"))
        XCTAssertEqual(edit.rebase(span(1)), span(1))
        XCTAssertEqual(edit.rebase(span(2)), span(3))
    }

    func testAnIndentedLinePastedAboveMovesTheSpanDown() throws {
        // The pasted line shares its indentation with the one below, so the
        // change could be read as starting inside that line. It must not be.
        let edit = try edit(source, source.replacingOccurrences(of: "{\n", with: "{\n    // note\n"))
        XCTAssertEqual(edit.rebase(span(2)), span(3))
    }

    func testAnIndentedLineDeletedAboveMovesTheSpanUp() throws {
        let longer = source.replacingOccurrences(of: "{\n", with: "{\n    // note\n")
        let edit = try edit(longer, source)
        XCTAssertNil(edit.rebase(span(2)), "the deleted line's own marker goes with it")
        XCTAssertEqual(edit.rebase(span(3)), span(2))
    }

    func testReturnAtTheEndOfTheReportedLineKeepsItsSpan() throws {
        let edit = try edit(source, source.replacingOccurrences(of: "\"a\";\n", with: "\"a\";\n\n"))
        XCTAssertEqual(edit.rebase(span(2)), span(2))
        XCTAssertEqual(edit.rebase(span(3)), span(4))
    }

    func testReturnAtTheEndOfTheFileKeepsTheLastLinesSpan() throws {
        let edit = try edit(source, source + "\n")
        XCTAssertEqual(edit.rebase(span(4)), span(4))
    }

    func testJoiningTwoLinesDropsBothTheirSpans() throws {
        let edit = try edit(
            source,
            source.replacingOccurrences(of: "\"a\";\n    println", with: "\"a\"; println")
        )
        XCTAssertNil(edit.rebase(span(2)))
        XCTAssertNil(edit.rebase(span(3)))
        XCTAssertEqual(edit.rebase(span(4)), span(3))
    }

    func testASpanAcrossTheEditedLineIsDropped() throws {
        let edit = try edit(source, source.replacingOccurrences(of: "{x}", with: "{x}!"))
        XCTAssertNil(edit.rebase(span(2, to: 4)))
    }

    func testAMultiLineSpanGrowsAroundALineInsertedInsideIt() throws {
        let edit = try edit(source, source.replacingOccurrences(of: "\"a\";\n", with: "\"a\";\n\n"))
        XCTAssertEqual(edit.rebase(span(1, to: 4)), span(1, to: 5))
    }
}

@MainActor
final class EditorDiagnosticMarkerTests: XCTestCase {
    private final class Box: ObservableObject {
        @Published var text = "fn main() {\n    let x: i32 = \"a\";\n    println!(\"{x}\");\n}"
        @Published var cursor = 0
        @Published var diagnostics: [RustDiagnostic] = []
    }

    private struct Host: View {
        @ObservedObject var box: Box
        var body: some View {
            SyntaxCodeEditor(
                text: $box.text,
                cursorOffset: $box.cursor,
                filePath: "main.rs",
                isEditable: true,
                diagnostics: box.diagnostics,
                navigationTarget: nil,
                onRequestCompletion: {}
            )
        }
    }

    private func findTextView(_ view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(subview) { return found }
        }
        return nil
    }

    /// rustc's E0308 for the second line: `"a"` is columns 18 to 21.
    private func mismatchedTypes(columnEnd: Int = 21) -> RustDiagnostic {
        RustDiagnostic(
            level: "error",
            message: "mismatched types",
            code: "E0308",
            rendered: "error[E0308]: mismatched types",
            spans: [
                RustDiagnostic.Span(
                    fileName: "main.rs",
                    lineStart: 2,
                    lineEnd: 2,
                    columnStart: 18,
                    columnEnd: columnEnd,
                    isPrimary: true,
                    label: "expected `i32`, found `&str`",
                    sourceLine: "    let x: i32 = \"a\";"
                ),
            ]
        )
    }

    private func makeEditor(_ box: Box) throws -> (UITextView, UIWindow) {
        let controller = UIHostingController(rootView: Host(box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let textView = try XCTUnwrap(findTextView(controller.view), "no UITextView was created")
        return (textView, window)
    }

    /// The text under every diagnostic underline, in order.
    private func underlined(in textView: UITextView) -> [String] {
        var found: [String] = []
        let storage = textView.textStorage
        storage.enumerateAttribute(
            .underlineStyle,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            guard let style = value as? Int, style != 0 else { return }
            found.append(storage.attributedSubstring(from: range).string)
        }
        return found
    }

    private func line(of substring: String, in textView: UITextView) -> Int {
        let text = textView.text as NSString
        let range = text.range(of: substring)
        return 1 + text.substring(to: range.location).filter { $0 == "\n" }.count
    }

    func testFixingTheReportedLineClearsItsUnderlineUntilTheNextBuild() throws {
        let box = Box()
        box.diagnostics = [mismatchedTypes()]
        let (textView, window) = try makeEditor(box)
        defer { window.isHidden = true }
        XCTAssertEqual(underlined(in: textView), ["\"a\""], "the build's span is underlined")

        // The reader fixes the line the compiler complained about.
        let literal = (textView.text as NSString).range(of: "\"a\"")
        textView.selectedRange = NSRange(location: NSMaxRange(literal), length: 0)
        textView.insertText(".len() as i32")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(box.text, textView.text)
        XCTAssertEqual(underlined(in: textView), [], "an edited line must not stay marked")
        XCTAssertFalse(box.diagnostics.isEmpty, "only the marker goes; the problem list is the build's")

        // The next build reports against the new text, and its marks show.
        box.diagnostics = [mismatchedTypes(columnEnd: 34)]
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(underlined(in: textView), ["\"a\".len() as i32"])
    }

    func testTheUnderlineFollowsItsLineWhenLinesAreInsertedAbove() throws {
        let box = Box()
        box.diagnostics = [mismatchedTypes()]
        let (textView, window) = try makeEditor(box)
        defer { window.isHidden = true }
        XCTAssertEqual(line(of: "\"a\"", in: textView), 2)

        // Return at the end of the first line, then a comment on the new one.
        let brace = (textView.text as NSString).range(of: "{")
        textView.selectedRange = NSRange(location: NSMaxRange(brace), length: 0)
        textView.insertText("\n")
        textView.insertText("    // the type is the problem")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(line(of: "\"a\"", in: textView), 3)
        XCTAssertEqual(
            underlined(in: textView), ["\"a\""],
            "the mark stays on the line it was reported for"
        )
    }
}
