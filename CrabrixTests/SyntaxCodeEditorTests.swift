import XCTest
import SwiftUI
import UIKit
@testable import Crabrix

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

        let textView = try XCTUnwrap(findTextView(controller.view))

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
            textView.contentSize.width, textView.bounds.width,
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

    /// A file long enough to scroll and wide enough to need sideways scrolling.
    private func makeEditor(lines: Int = 400) throws -> (UITextView, UIWindow) {
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

        let textView = try XCTUnwrap(findTextView(controller.view), "no UITextView was created")
        textView.layoutIfNeeded()
        return (textView, window)
    }

    func testALongFileScrollsPastTheFirstLineAndStaysThere() throws {
        let (textView, window) = try makeEditor()
        defer { window.isHidden = true }

        XCTAssertGreaterThan(
            textView.contentSize.height, textView.bounds.height,
            "a 400-line file has to be taller than the viewport to scroll at all"
        )

        textView.contentOffset = CGPoint(x: 0, y: 1_200)
        // Several layout passes, which is what scrolling actually causes.
        for _ in 0..<4 { textView.layoutIfNeeded() }

        XCTAssertEqual(
            textView.contentOffset.y, 1_200, accuracy: 1,
            "layout must not drag the reader back to the first line"
        )
    }

    func testHorizontalScrollPositionSurvivesLayout() throws {
        let (textView, window) = try makeEditor()
        defer { window.isHidden = true }

        XCTAssertGreaterThan(
            textView.contentSize.width, textView.bounds.width,
            "long lines have to make the content wider than the viewport"
        )

        textView.contentOffset = CGPoint(x: 220, y: 600)
        for _ in 0..<4 { textView.layoutIfNeeded() }

        XCTAssertEqual(textView.contentOffset.x, 220, accuracy: 1)
        XCTAssertEqual(textView.contentOffset.y, 600, accuracy: 1)
    }

    func testTheGutterStaysOverTheVisibleLeftEdgeWhenScrolledSideways() throws {
        let (textView, window) = try makeEditor()
        defer { window.isHidden = true }

        textView.contentOffset = CGPoint(x: 260, y: 400)
        textView.layoutIfNeeded()

        // The gutter is a subview so the text cannot composite over it; it has
        // to travel with the viewport rather than staying at content x = 0.
        let gutter = try XCTUnwrap(
            textView.subviews.first { String(describing: type(of: $0)).contains("Gutter") }
        )
        XCTAssertEqual(gutter.frame.minX, 260, accuracy: 1, "the gutter must follow the viewport")
        XCTAssertEqual(gutter.frame.minY, 400, accuracy: 1)
        XCTAssertNotNil(gutter.backgroundColor, "a transparent gutter lets code show through")
        XCTAssertEqual(
            textView.subviews.last, gutter,
            "the gutter has to stay in front of the text"
        )
    }

    func testTypingDoesNotResetTheScrollPosition() throws {
        let (textView, window) = try makeEditor()
        defer { window.isHidden = true }

        textView.contentOffset = CGPoint(x: 0, y: 900)
        textView.layoutIfNeeded()
        textView.insertText("// a comment\n")
        textView.layoutIfNeeded()

        XCTAssertGreaterThan(
            textView.contentOffset.y, 0,
            "editing must not jump the reader back to the top"
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

    func testRepaintingDoesNotDragTheReaderBackToTheFirstLine() throws {
        let box = Box()
        box.text = (0..<500).map { "let value_\($0) = \($0);" }.joined(separator: "\n")

        let controller = UIHostingController(rootView: Host(box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()

        let textView = try XCTUnwrap(findTextView(controller.view))
        let coordinator = try XCTUnwrap(textView.delegate as? SyntaxCodeEditor.Coordinator)

        // Caret near the top, reader scrolled well past it — the situation
        // where re-applying the selection is visibly wrong.
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.layoutIfNeeded()
        textView.contentOffset = CGPoint(x: 0, y: 2_000)
        textView.layoutIfNeeded()

        // A repaint — theme change, font change, a re-render from anywhere.
        coordinator.applyHighlighting(to: textView, filePath: "src/main.rs")
        textView.layoutIfNeeded()

        XCTAssertEqual(
            textView.contentOffset.y, 2_000, accuracy: 1,
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
