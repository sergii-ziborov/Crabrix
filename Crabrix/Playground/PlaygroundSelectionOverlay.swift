import UIKit

/// Decorations live inside the existing text canvas, so they follow horizontal
/// and vertical scrolling without changing editor or Duo layout measurements.
final class PlaygroundSelectionOverlay: UIView {
    private struct Mark { let rectangles: [CGRect]; let caret: CGRect; let color: UIColor; let name: String }
    private var marks: [Mark] = []
    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; backgroundColor = .clear; isAccessibilityElement = false }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    func update(textView: UITextView, selections: [PlaygroundRemoteSelection]) {
        let length = (textView.text as NSString?)?.length ?? 0
        marks = selections.prefix(3).compactMap { selection in
            guard selection.anchor >= 0, selection.head >= 0, selection.anchor <= length, selection.head <= length,
                  let begin = textView.position(from: textView.beginningOfDocument, offset: selection.range.location),
                  let end = textView.position(from: begin, offset: selection.range.length),
                  let range = textView.textRange(from: begin, to: end),
                  let head = textView.position(from: textView.beginningOfDocument, offset: selection.head),
                  let hex = UInt32(selection.color.dropFirst(), radix: 16) else { return nil }
            let color = UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
            return Mark(rectangles: textView.selectionRects(for: range).map(\.rect), caret: textView.caretRect(for: head), color: color, name: String(selection.name.prefix(40)))
        }
        setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        for mark in marks {
            mark.color.withAlphaComponent(0.24).setFill()
            for area in mark.rectangles { UIBezierPath(rect: area).fill() }
            mark.color.setFill()
            let caret = CGRect(x: mark.caret.minX, y: mark.caret.minY, width: 2, height: max(12, mark.caret.height))
            UIBezierPath(rect: caret).fill()
            let font = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let text = mark.name as NSString, size = text.size(withAttributes: attributes)
            let badge = CGRect(x: min(max(0, caret.minX), max(0, bounds.width - size.width - 8)), y: max(0, caret.minY - 17), width: size.width + 8, height: 16)
            UIBezierPath(roundedRect: badge, cornerRadius: 3).fill()
            text.draw(at: CGPoint(x: badge.minX + 4, y: badge.minY + 1), withAttributes: attributes)
        }
    }
}
