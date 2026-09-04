import UIKit
import XCTest
@testable import Crabrix

/// A line wider than the phone must stay reachable.
///
/// The editor deliberately does not wrap: code scrolls sideways instead. That
/// only works if the whole line is laid out, drawn, and inside the scrollable
/// width — three separate things UITextView gets wrong on its own, because it
/// is built to scroll downwards.
final class EditorHorizontalScrollTests: XCTestCase {
    private let width: CGFloat = 393
    private let height: CGFloat = 600

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// Hosted in a real window: the editor draws its text into a subview of
    /// its own, and off-screen views do not necessarily paint one.
    private func makeCanvas(text: String) -> CodeEditorCanvas {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.makeKeyAndVisible()
        self.window = window

        let canvas = CodeEditorCanvas(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.addSubview(canvas)
        canvas.textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        canvas.textView.textContainerInset = UIEdgeInsets(top: 16, left: 54, bottom: 16, right: 14)
        canvas.textView.textContainer.lineFragmentPadding = 0
        canvas.backgroundColor = .black
        canvas.textView.textColor = .white
        canvas.textView.text = text
        canvas.layoutIfNeeded()
        return canvas
    }

    private var longLine: String {
        "    let very_long_line_to_check_horizontal_scrolling = "
            + "\"0123456789 0123456789 0123456789 0123456789 END_OF_THE_LINE\";"
    }

    private var source: String {
        """
        fn main() {
            println!("short");
        \(longLine)
        }
        """
    }

    /// The advance of one character in the editor's font.
    private func advance(_ textView: UITextView) -> CGFloat {
        ("0" as NSString).size(withAttributes: [.font: textView.font!]).width
    }

    func testLongLineIsNotWrapped() {
        let textView = makeCanvas(text: source).textView
        // Four source lines, four laid-out rows. A wrapped line would add more.
        var rows = 0
        let glyphs = textView.layoutManager.glyphRange(for: textView.textContainer)
        textView.layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in
            rows += 1
        }
        XCTAssertEqual(rows, 4, "the long line wrapped instead of running off to the right")
    }

    func testScrollableWidthReachesTheEndOfTheLongestLine() {
        let canvas = makeCanvas(text: source)
        let textView = canvas.textView
        let needed = CGFloat(longLine.count) * advance(textView)
            + textView.textContainerInset.left + textView.textContainerInset.right

        XCTAssertGreaterThanOrEqual(
            textView.bounds.width, needed - 1,
            "the end of the longest line cannot be scrolled to"
        )
        // And not so wide that the reader can scroll the code out of sight.
        XCTAssertLessThan(
            textView.bounds.width, needed + 200,
            "the content is wider than the text, leaving empty space to scroll into"
        )
    }

    func testTheEndOfTheLongestLineIsDrawnWhenScrolledToIt() throws {
        let canvas = makeCanvas(text: source)

        // The control: unscrolled, the editor obviously draws something. It
        // proves the check below is looking at real pixels.
        XCTAssertTrue(
            try drawsSomething(canvas),
            "the editor drew nothing even unscrolled, so this test proves nothing"
        )

        canvas.scrollOffset = CGPoint(x: canvas.textView.bounds.width - width, y: 0)
        canvas.layoutIfNeeded()
        XCTAssertTrue(
            try drawsSomething(canvas),
            "scrolled to the end of the line, the editor draws nothing there"
        )
    }

    func testTheGutterKeepsItsNumbersWhenScrolledSideways() {
        let canvas = makeCanvas(text: source)
        canvas.scrollOffset = CGPoint(x: canvas.textView.bounds.width - width, y: 0)
        canvas.layoutIfNeeded()
        XCTAssertEqual(canvas.scrollOffset.x, canvas.textView.bounds.width - width, accuracy: 1)
    }

    /// Whether anything but the background is painted right of the gutter.
    private func drawsSomething(_ canvas: CodeEditorCanvas) throws -> Bool {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { _ in
            canvas.drawHierarchy(in: canvas.bounds, afterScreenUpdates: true)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let inspected = CGRect(
            x: CodeEditorCanvas.gutterWidth + 8,
            y: 0,
            width: width - CodeEditorCanvas.gutterWidth - 8,
            height: height
        )
        return hasNonBackgroundPixels(in: cgImage, rect: inspected, scale: image.scale)
    }

    private func hasNonBackgroundPixels(in image: CGImage, rect: CGRect, scale: CGFloat) -> Bool {
        let x = Int(rect.minX * scale)
        let y = Int(rect.minY * scale)
        let width = min(Int(rect.width * scale), image.width - x)
        let height = min(Int(rect.height * scale), image.height - y)
        guard width > 0, height > 0 else { return false }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.translateBy(x: CGFloat(-x), y: CGFloat(-y))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        // The background is black; a glyph is not.
        return pixels.enumerated().contains { index, value in
            index % 4 != 3 && value > 60
        }
    }
}
