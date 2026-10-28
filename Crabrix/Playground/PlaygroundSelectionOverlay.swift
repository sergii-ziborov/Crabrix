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
        var badges: [CGRect] = []
        for mark in marks {
            mark.color.withAlphaComponent(0.24).setFill()
            for area in mark.rectangles { UIBezierPath(rect: area).fill() }
            mark.color.setFill()
            let caret = CGRect(x: mark.caret.minX, y: mark.caret.minY, width: 2, height: max(12, mark.caret.height))
            UIBezierPath(rect: caret).fill()
            let font = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let text = mark.name as NSString, size = text.size(withAttributes: attributes)
            guard let badge = Self.badgeFrame(preferred: CGRect(x: caret.minX, y: max(0, caret.minY - 17), width: size.width + 8, height: 16),
                                             inside: bounds, occupied: badges) else { continue }
            badges.append(badge)
            UIBezierPath(roundedRect: badge, cornerRadius: 3).fill()
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            var labelAttributes = attributes; labelAttributes[.paragraphStyle] = paragraph
            text.draw(in: badge.insetBy(dx: 4, dy: 1), withAttributes: labelAttributes)
        }
    }

    /// Nearby collaborators can point at the same word. Keep names separate
    /// inside the existing overlay; this never changes editor/keyboard geometry.
    static func badgeFrame(preferred: CGRect, inside bounds: CGRect, occupied: [CGRect]) -> CGRect? {
        let width = min(preferred.width, bounds.width), height = preferred.height
        guard width >= 8, height > 0, bounds.height >= height else { return nil }
        let x = min(max(bounds.minX, preferred.minX), bounds.maxX - width)
        let y = min(max(bounds.minY, preferred.minY), bounds.maxY - height)
        var columns: [CGFloat] = [x, bounds.minX, bounds.maxX - width]
        for frame in occupied {
            columns.append(frame.maxX + 4)
            columns.append(frame.minX - width - 4)
        }
        let allowed = columns.filter { $0 >= bounds.minX && $0 + width <= bounds.maxX }
        let xs = allowed.sorted { abs($0 - x) < abs($1 - x) }
        for offset in [CGFloat(0), -18, 18, -36, 36] {
            let row = y + offset
            guard row >= bounds.minY, row + height <= bounds.maxY else { continue }
            for column in xs {
                let candidate = CGRect(x: column, y: row, width: width, height: height)
                if occupied.allSatisfy({ !$0.insetBy(dx: -2, dy: -1).intersects(candidate) }) { return candidate }
            }
        }
        return nil
    }
}
