import SwiftUI
import UIKit

struct EditorNavigationTarget: Equatable {
    let id = UUID()
    let filePath: String
    let line: Int
    let column: Int
}

struct SyntaxCodeEditor: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("crabrix.editorFontSize") private var editorFontSize = 14.0
    @Binding var text: String
    @Binding var cursorOffset: Int
    let projectID: UUID?
    let filePath: String
    let isEditable: Bool
    let tracksTyping: Bool
    let diagnostics: [RustDiagnostic]
    let navigationTarget: EditorNavigationTarget?
    /// Whether the assistant key will actually reach Apple Intelligence. When
    /// it will not, the key still completes Rust offline — it just stops
    /// wearing Apple Intelligence's sparkle to say so.
    let assistantUsesAppleIntelligence: Bool
    let onRequestCompletion: () -> Void

    init(
        text: Binding<String>,
        cursorOffset: Binding<Int>,
        projectID: UUID? = nil,
        filePath: String,
        isEditable: Bool,
        tracksTyping: Bool = true,
        diagnostics: [RustDiagnostic] = [],
        navigationTarget: EditorNavigationTarget?,
        assistantUsesAppleIntelligence: Bool = false,
        onRequestCompletion: @escaping () -> Void
    ) {
        _text = text
        _cursorOffset = cursorOffset
        self.projectID = projectID
        self.filePath = filePath
        self.isEditable = isEditable
        self.tracksTyping = tracksTyping
        self.diagnostics = diagnostics
        self.navigationTarget = navigationTarget
        self.assistantUsesAppleIntelligence = assistantUsesAppleIntelligence
        self.onRequestCompletion = onRequestCompletion
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> CodeEditorCanvas {
        let canvas = CodeEditorCanvas(frame: .zero)
        let textView = canvas.textView
        textView.delegate = context.coordinator
        canvas.backgroundColor = UIColor(CrabrixTheme.editor)
        textView.textColor = UIColor(CrabrixTheme.primary)
        textView.tintColor = UIColor(CrabrixTheme.blue)
        textView.keyboardAppearance = colorScheme == .dark ? .dark : .light
        textView.font = .monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 54, bottom: 16, right: 14)
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.accessibilityLabel = "Rust source editor"
        canvas.lineNumberColor = UIColor(CrabrixTheme.muted).withAlphaComponent(0.82)
        canvas.gutterSeparatorColor = UIColor(CrabrixTheme.border)
        canvas.gutterBackgroundColor = UIColor(CrabrixTheme.editor)
        textView.text = text
        context.coordinator.textView = textView
        context.coordinator.canvas = canvas
        textView.inputAccessoryView = RustKeyboardAccessoryView(
            usesAppleIntelligence: assistantUsesAppleIntelligence,
            onInsert: { [weak coordinator = context.coordinator] symbol in
                coordinator?.insert(symbol)
            },
            onComplete: { [weak coordinator = context.coordinator] in
                coordinator?.parent.onRequestCompletion()
            },
            onDismiss: { [weak textView] in
                textView?.resignFirstResponder()
            }
        )
        context.coordinator.applyHighlighting(to: textView, filePath: filePath)
        return canvas
    }

    func updateUIView(_ canvas: CodeEditorCanvas, context: Context) {
        let textView = canvas.textView
        context.coordinator.parent = self
        context.coordinator.canvas = canvas
        (textView.inputAccessoryView as? RustKeyboardAccessoryView)?
            .setUsesAppleIntelligence(assistantUsesAppleIntelligence)
        textView.isEditable = isEditable
        canvas.backgroundColor = UIColor(CrabrixTheme.editor)
        textView.keyboardAppearance = colorScheme == .dark ? .dark : .light
        canvas.lineNumberColor = UIColor(CrabrixTheme.muted).withAlphaComponent(0.82)
        canvas.gutterSeparatorColor = UIColor(CrabrixTheme.border)
        canvas.gutterBackgroundColor = UIColor(CrabrixTheme.editor)
        if textView.text != text {
            textView.text = text
            textView.selectedRange = NSRange(
                location: min(cursorOffset, (text as NSString).length),
                length: 0
            )
        }
        if context.coordinator.highlightedText != text
            || context.coordinator.highlightedFilePath != filePath
            || context.coordinator.highlightedFontSize != editorFontSize
            || context.coordinator.highlightedColorScheme != colorScheme
            || context.coordinator.highlightedDiagnosticsSignature != diagnosticsSignature {
            context.coordinator.applyHighlighting(to: textView, filePath: filePath)
        }
        if let navigationTarget,
           navigationTarget.filePath == filePath,
           context.coordinator.lastNavigationID != navigationTarget.id {
            context.coordinator.applyHighlighting(to: textView, filePath: filePath)
            context.coordinator.reveal(navigationTarget, in: textView)
            canvas.setNeedsSizeUpdate()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SyntaxCodeEditor
        var highlightedText = ""
        var highlightedFilePath = ""
        var highlightedFontSize = 0.0
        var highlightedColorScheme: ColorScheme?
        var highlightedDiagnosticsSignature = ""
        weak var textView: UITextView?
        weak var canvas: CodeEditorCanvas?
        var lastNavigationID: UUID?
        private var isApplyingHighlight = false

        init(parent: SyntaxCodeEditor) {
            self.parent = parent
        }

        /// Classifies every insertion before it lands.
        ///
        /// Length is the signal: a keystroke or an accessory symbol is short, a
        /// paste or an accepted completion is not. This is the only place that
        /// sees the difference — by `textViewDidChange` it is just new text.
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if parent.tracksTyping, let projectID = parent.projectID, !text.isEmpty {
                TypingLedger.shared.record(
                    projectID: projectID,
                    filePath: parent.filePath,
                    inserted: text
                )
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            // Typing edits the text storage directly, so the `text` setter
            // that normally schedules the measurement never runs. Without
            // this, a line typed past the right edge stays unreachable.
            canvas?.setNeedsSizeUpdate()
            parent.text = textView.text
            parent.cursorOffset = textView.selectedRange.location
            applyHighlighting(to: textView, filePath: parent.filePath, preservingScroll: false)
            canvas?.layoutIfNeeded()
            canvas?.scrollCaretToVisible()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            let offset = textView.selectedRange.location
            guard parent.cursorOffset != offset else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.cursorOffset = offset
            }
        }

        func insert(_ symbol: String) {
            guard let textView else { return }
            let source = textView.text ?? ""
            let range = textView.selectedRange
            let updated = (source as NSString).replacingCharacters(in: range, with: symbol)
            let cursor = range.location + (symbol as NSString).length
            textView.text = updated
            textView.selectedRange = NSRange(location: cursor, length: 0)
            parent.text = updated
            parent.cursorOffset = cursor
            applyHighlighting(to: textView, filePath: parent.filePath, preservingScroll: false)
            canvas?.layoutIfNeeded()
            canvas?.scrollCaretToVisible()
        }

        /// Repaints the syntax colours.
        ///
        /// - Parameter preservingScroll: true when this is a repaint rather than
        ///   something the reader did. Re-applying a selection makes UITextView
        ///   scroll it into view, so a repaint with the caret still at offset 0
        ///   would yank a reader who had scrolled down back to the first line.
        ///   Typing passes false, because there the caret should lead.
        func applyHighlighting(
            to textView: UITextView,
            filePath: String,
            preservingScroll: Bool = true
        ) {
            let source = textView.text ?? ""
            let fullRange = NSRange(location: 0, length: (source as NSString).length)
            let selection = textView.selectedRange
            let offsetBefore = canvas?.scrollOffset ?? .zero
            let baseFont = UIFont.monospacedSystemFont(
                ofSize: parent.editorFontSize,
                weight: .regular
            )
            let base: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: UIColor(CrabrixTheme.primary),
            ]

            isApplyingHighlight = true
            textView.textStorage.beginEditing()
            textView.textStorage.setAttributes(base, range: fullRange)
            for token in SyntaxHighlighter.tokens(in: source, filePath: filePath) {
                guard NSMaxRange(token.range) <= fullRange.length else { continue }
                textView.textStorage.addAttribute(
                    .foregroundColor,
                    value: color(for: token.kind),
                    range: token.range
                )
            }
            for diagnostic in parent.diagnostics {
                for span in diagnostic.spans where matches(span.fileName, filePath) {
                    guard let range = diagnosticRange(for: span, in: source),
                          NSMaxRange(range) <= fullRange.length
                    else { continue }
                    let style: NSUnderlineStyle = span.isPrimary ? .thick : .single
                    let color = diagnostic.level == "warning"
                        ? UIColor(CrabrixTheme.amber)
                        : UIColor(CrabrixTheme.coral)
                    textView.textStorage.addAttributes(
                        [
                            .underlineStyle: style.rawValue,
                            .underlineColor: color,
                        ],
                        range: range
                    )
                }
            }
            textView.textStorage.endEditing()
            textView.typingAttributes = base
            // Only when it actually moved: assigning an unchanged selection
            // still scrolls, which is the whole bug.
            if textView.selectedRange != selection {
                textView.selectedRange = selection
            }
            if preservingScroll, let canvas, canvas.scrollOffset != offsetBefore {
                canvas.scrollOffset = offsetBefore
            }
            isApplyingHighlight = false
            highlightedText = source
            highlightedFilePath = filePath
            highlightedFontSize = parent.editorFontSize
            highlightedColorScheme = parent.colorScheme
            highlightedDiagnosticsSignature = parent.diagnosticsSignature
        }

        func reveal(_ target: EditorNavigationTarget, in textView: UITextView) {
            guard let lineRange = lineRange(target.line, in: textView.text ?? "") else { return }
            lastNavigationID = target.id
            textView.textStorage.addAttribute(
                .backgroundColor,
                value: UIColor(CrabrixTheme.amber).withAlphaComponent(0.22),
                range: lineRange
            )
            let cursor = min(
                lineRange.location + max(target.column - 1, 0),
                NSMaxRange(lineRange)
            )
            textView.selectedRange = NSRange(location: cursor, length: 0)
            parent.cursorOffset = cursor
            canvas?.layoutIfNeeded()
            canvas?.scrollRangeToVisible(lineRange)
            UIAccessibility.post(
                notification: .announcement,
                argument: "Opened \(target.filePath), line \(target.line)"
            )
        }

        private func lineRange(_ requestedLine: Int, in source: String) -> NSRange? {
            guard requestedLine > 0 else { return nil }
            let string = source as NSString
            var location = 0
            if requestedLine > 1 {
                for _ in 1..<requestedLine {
                    let search = NSRange(location: location, length: string.length - location)
                    let newline = string.range(of: "\n", options: [], range: search)
                    guard newline.location != NSNotFound else { return nil }
                    location = NSMaxRange(newline)
                }
            }
            let remainder = NSRange(location: location, length: string.length - location)
            let newline = string.range(of: "\n", options: [], range: remainder)
            let end = newline.location == NSNotFound ? string.length : newline.location
            let length = newline.location == NSNotFound
                ? end - location
                : max(end - location, 1)
            return NSRange(location: location, length: length)
        }

        private func diagnosticRange(
            for span: RustDiagnostic.Span,
            in source: String
        ) -> NSRange? {
            guard let firstLine = lineRange(span.lineStart, in: source),
                  let lastLine = lineRange(span.lineEnd, in: source)
            else { return nil }

            let start = min(
                firstLine.location + max(span.columnStart - 1, 0),
                NSMaxRange(firstLine)
            )
            let end = min(
                lastLine.location + max(span.columnEnd - 1, 0),
                NSMaxRange(lastLine)
            )
            let upperBound = max(end, min(start + 1, (source as NSString).length))
            guard upperBound > start else { return nil }
            return NSRange(location: start, length: upperBound - start)
        }

        private func matches(_ diagnosticPath: String, _ editorPath: String) -> Bool {
            diagnosticPath == editorPath
                || diagnosticPath.hasSuffix("/\(editorPath)")
                || editorPath.hasSuffix("/\(diagnosticPath)")
        }

        private func color(for kind: SyntaxTokenKind) -> UIColor {
            SyntaxTheme.uiColor(for: kind)
        }
    }

    private var diagnosticsSignature: String {
        diagnostics.map { diagnostic in
            let spans = diagnostic.spans.map {
                "\($0.fileName):\($0.lineStart):\($0.columnStart):\($0.lineEnd):\($0.columnEnd)"
            }.joined(separator: ",")
            return "\(diagnostic.id.uuidString):\(diagnostic.level):\(spans)"
        }.joined(separator: "|")
    }
}

/// The editor surface: a scroll view holding a text view sized to the whole
/// file, with the line numbers pinned over its left edge.
///
/// UITextView scrolls itself, but only downwards. It lays the glyphs into a
/// subview it keeps at its own width, and forces the text container back to
/// that width on every layout pass, so a line wider than the screen is either
/// wrapped or clipped at the right edge — laid out, sometimes even scrollable,
/// and never drawn. Making the text view as wide as the widest line and
/// scrolling it from outside is what puts the whole line on screen.
final class CodeEditorCanvas: UIView {
    let textView: RustSourceTextView
    private let scrollView = UIScrollView()

    /// Width reserved for line numbers, matching `textContainerInset.left`.
    static let gutterWidth: CGFloat = 44

    var lineNumberColor = UIColor.secondaryLabel {
        didSet { gutterView.lineNumberColor = lineNumberColor }
    }
    var gutterSeparatorColor = UIColor.separator {
        didSet { gutterView.separatorColor = gutterSeparatorColor }
    }
    var gutterBackgroundColor: UIColor = .clear {
        didSet { gutterView.backgroundColor = gutterBackgroundColor }
    }

    /// A sibling of the scroll view, so the code slides underneath it and the
    /// numbers stay put however far sideways the reader goes.
    private lazy var gutterView: GutterView = {
        let view = GutterView()
        view.isUserInteractionEnabled = false
        view.contentMode = .redraw
        view.backgroundColor = gutterBackgroundColor
        return view
    }()

    private var needsSizeUpdate = true
    private var lastLaidOutBounds = CGSize.zero

    override init(frame: CGRect) {
        textView = RustSourceTextView()
        super.init(frame: frame)

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self

        textView.isScrollEnabled = false
        textView.onLayoutChanged = { [weak self] in self?.setNeedsSizeUpdate() }

        addSubview(scrollView)
        scrollView.addSubview(textView)
        addSubview(gutterView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CodeEditorCanvas is created in code, never from a nib")
    }

    override var backgroundColor: UIColor? {
        didSet {
            scrollView.backgroundColor = backgroundColor
            textView.backgroundColor = backgroundColor
        }
    }

    /// Where the file is scrolled to, in content coordinates.
    var scrollOffset: CGPoint {
        get { scrollView.contentOffset }
        set { scrollView.setContentOffset(clamped(newValue), animated: false) }
    }

    func setNeedsSizeUpdate() {
        needsSizeUpdate = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if scrollView.frame != bounds { scrollView.frame = bounds }
        if lastLaidOutBounds != bounds.size {
            lastLaidOutBounds = bounds.size
            needsSizeUpdate = true
        }
        if needsSizeUpdate {
            needsSizeUpdate = false
            resizeTextView()
        }
        gutterView.frame = CGRect(x: 0, y: 0, width: Self.gutterWidth, height: bounds.height)
        if subviews.last !== gutterView { bringSubviewToFront(gutterView) }
        positionGutter()
    }

    private func resizeTextView() {
        let size = textView.sizeForWholeFile(fitting: bounds.size)
        guard size.width > 0, size.height > 0 else { return }
        if textView.frame.size != size {
            textView.frame = CGRect(origin: .zero, size: size)
        }
        if scrollView.contentSize != size {
            let previous = scrollView.contentOffset
            scrollView.contentSize = size
            // Shrinking the content clamps the offset, and the reader did not
            // ask to be moved.
            let restored = clamped(previous)
            if scrollView.contentOffset != restored { scrollView.contentOffset = restored }
        }
        scrollView.alwaysBounceHorizontal = size.width > bounds.width + 0.5
    }

    private func clamped(_ offset: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, offset.x), max(0, scrollView.contentSize.width - bounds.width)),
            y: min(max(0, offset.y), max(0, scrollView.contentSize.height - bounds.height))
        )
    }

    private func positionGutter() {
        if let font = textView.font {
            gutterView.numberFont = .monospacedDigitSystemFont(
                ofSize: max(font.pointSize - 3, 9),
                weight: .regular
            )
        }
        gutterView.verticalOffset = scrollView.contentOffset.y
        gutterView.lines = textView.lineNumbers(in: CGRect(
            origin: scrollView.contentOffset,
            size: bounds.size
        ))
        gutterView.setNeedsDisplay()
    }

    /// Brings a range of the file into view without moving more than it must.
    func scrollRangeToVisible(_ range: NSRange, animated: Bool = false) {
        guard let rect = textView.rect(for: range) else { return }
        scrollView.scrollRectToVisible(
            rect.insetBy(dx: -Self.gutterWidth, dy: -24),
            animated: animated
        )
    }

    /// Keeps the caret in view while typing, which the text view would do for
    /// itself if it were the one scrolling.
    func scrollCaretToVisible() {
        guard let selection = textView.selectedTextRange else { return }
        var caret = textView.caretRect(for: selection.end)
        guard caret.isFinite else { return }
        caret = caret.insetBy(dx: -(Self.gutterWidth + 24), dy: -12)
        scrollView.scrollRectToVisible(caret, animated: false)
    }
}

extension CodeEditorCanvas: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        positionGutter()
    }
}

/// The text view itself: never scrolls, never wraps, and is laid out at the
/// size of the whole file by the canvas around it.
final class RustSourceTextView: UITextView {
    /// Called when the text or the font may have changed the laid-out size.
    var onLayoutChanged: (() -> Void)?

    /// Its own TextKit 1 stack, so the line breaking is ours to set.
    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 1, height: 1))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineBreakMode = .byClipping
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RustSourceTextView is created in code, never from a nib")
    }

    override var text: String! {
        didSet { onLayoutChanged?() }
    }

    override var font: UIFont? {
        didSet { onLayoutChanged?() }
    }

    override var textContainerInset: UIEdgeInsets {
        didSet { onLayoutChanged?() }
    }

    /// The size at which every line is fully laid out and fully drawn.
    ///
    /// - Parameter visible: the size of the window onto the file, which the
    ///   result never goes below: a short file still fills the screen, so a tap
    ///   under the last line lands in the editor.
    func sizeForWholeFile(fitting visible: CGSize) -> CGSize {
        let horizontalInset = textContainerInset.left + textContainerInset.right
        let verticalInset = textContainerInset.top + textContainerInset.bottom
        let available = max(visible.width - horizontalInset, 1)

        // Room to lay the longest line out in one piece...
        setContainerWidth(max(available, estimatedLongestLineWidth()))
        layoutManager.ensureLayout(for: textContainer)
        let used = laidOutTextSize()

        // ...then only as much of it as the text actually filled, because the
        // container is what the scrollable width is built from and headroom
        // here is empty space the reader can scroll the code out of view into.
        setContainerWidth(max(available, used.width + 8))
        layoutManager.ensureLayout(for: textContainer)

        return CGSize(
            width: max(visible.width, ceil(used.width) + horizontalInset + 8),
            height: max(visible.height, ceil(used.height) + verticalInset)
        )
    }

    /// The rect a range occupies, in this view's coordinates.
    func rect(for range: NSRange) -> CGRect? {
        guard range.location <= (text as NSString?)?.length ?? 0 else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        guard rect.isFinite else { return nil }
        return rect.offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
    }

    /// The line numbers inside a rect, with their y in this view's coordinates.
    func lineNumbers(in visible: CGRect) -> [GutterView.Line] {
        let source = text ?? ""
        guard !source.isEmpty else {
            return [GutterView.Line(number: 1, y: textContainerInset.top)]
        }

        let lineStarts = logicalLineStarts(in: source)
        let inContainer = visible.offsetBy(dx: -textContainerInset.left, dy: -textContainerInset.top)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: inContainer, in: textContainer)

        var lines: [GutterView.Line] = []
        var seen: Set<Int> = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] rect, _, _, glyphRange, _ in
            guard let self, glyphRange.location < self.layoutManager.numberOfGlyphs else { return }
            let characterIndex = self.layoutManager.characterIndexForGlyph(at: glyphRange.location)
            let line = self.lineNumber(at: characterIndex, starts: lineStarts)
            guard seen.insert(line).inserted else { return }
            lines.append(GutterView.Line(number: line, y: rect.minY + self.textContainerInset.top))
        }
        return lines
    }

    private func setContainerWidth(_ width: CGFloat) {
        if textContainer.widthTracksTextView { textContainer.widthTracksTextView = false }
        if textContainer.heightTracksTextView { textContainer.heightTracksTextView = false }
        if textContainer.lineBreakMode != .byClipping { textContainer.lineBreakMode = .byClipping }
        let size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        if abs(textContainer.size.width - size.width) > 0.5
            || textContainer.size.height != size.height {
            textContainer.size = size
        }
    }

    /// How far the text actually reaches.
    ///
    /// Measured over the line fragments' own used rects: every rect that
    /// describes the container is as wide as the container, so it would report
    /// the headroom rather than the text.
    private func laidOutTextSize() -> CGSize {
        let glyphs = layoutManager.glyphRange(for: textContainer)
        guard glyphs.length > 0 else {
            return CGSize(width: 0, height: font?.lineHeight ?? 16)
        }
        var width: CGFloat = 0
        var height: CGFloat = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, usedRect, _, _, _ in
            width = max(width, usedRect.maxX)
            height = max(height, rect.maxY)
        }
        // A file ending in a newline has one more line to show than it has
        // laid-out fragments.
        if (text ?? "").hasSuffix("\n") { height += font?.lineHeight ?? 16 }
        return CGSize(width: width, height: height)
    }

    /// An upper bound on the widest line, in points.
    ///
    /// Counting characters keeps this cheap on a long file; the font is
    /// monospaced, so the count is the width. The doubling is headroom for
    /// scripts whose glyphs are wider than the advance — being generous costs
    /// nothing here, because the size that ends up used is measured from the
    /// glyphs that were actually laid out.
    private func estimatedLongestLineWidth() -> CGFloat {
        guard let font, let source = text, !source.isEmpty else { return 1 }
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        guard advance > 0 else { return 1 }

        var longest = 0
        var current = 0
        for character in source.unicodeScalars {
            switch character {
            case "\n":
                longest = max(longest, current)
                current = 0
            // A tab advances to the next tab stop, several characters wide.
            case "\t":
                current += 8
            default:
                current += 1
            }
        }
        longest = max(longest, current)
        return CGFloat(longest * 2 + 8) * advance
    }

    private func logicalLineStarts(in source: String) -> [Int] {
        let string = source as NSString
        var starts = [0]
        for index in 0..<string.length where string.character(at: index) == 10 {
            starts.append(index + 1)
        }
        return starts
    }

    private func lineNumber(at characterIndex: Int, starts: [Int]) -> Int {
        var lower = 0
        var upper = starts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if starts[middle] <= characterIndex { lower = middle + 1 }
            else { upper = middle }
        }
        return max(lower, 1)
    }
}

private extension CGRect {
    var isFinite: Bool {
        minX.isFinite && minY.isFinite && width.isFinite && height.isFinite
    }
}

/// Draws the line numbers, pinned over the visible left edge of the editor.
///
/// Separate from the text view's own drawing on purpose: text rendering
/// composites over anything the scroll view draws itself once the content
/// scrolls sideways, which is what put code on top of the numbers.
final class GutterView: UIView {
    struct Line: Equatable {
        let number: Int
        /// Position in the text view's content coordinates.
        let y: CGFloat
    }

    var lines: [Line] = []
    var verticalOffset: CGFloat = 0
    var lineNumberColor = UIColor.secondaryLabel
    var separatorColor = UIColor.separator
    var numberFont = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    override func draw(_ rect: CGRect) {
        // Opaque behind the numbers so code scrolling past cannot show through.
        backgroundColor?.setFill()
        UIRectFill(bounds)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: lineNumberColor,
        ]

        for line in lines {
            let y = line.y - verticalOffset
            guard y > -numberFont.lineHeight, y < bounds.height else { continue }
            let value = "\(line.number)" as NSString
            let size = value.size(withAttributes: attributes)
            value.draw(
                at: CGPoint(x: bounds.width - size.width - 8, y: y),
                withAttributes: attributes
            )
        }

        let separator = UIBezierPath()
        separator.move(to: CGPoint(x: bounds.maxX, y: bounds.minY))
        separator.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
        separatorColor.setStroke()
        separator.lineWidth = 1 / max(UIScreen.main.scale, 1)
        separator.stroke()
    }
}

private final class RustKeyboardAccessoryView: UIView {
    private let symbols = ["::", "->", "=>", "&", "&mut ", "|", "_", "!", "<", ">", "{", "}", "[", "]", "(", ")", ";"]
    private let completeButton: UIButton

    init(
        usesAppleIntelligence: Bool,
        onInsert: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        completeButton = Self.assistantButton(usesAppleIntelligence: usesAppleIntelligence)
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        autoresizingMask = .flexibleHeight

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        completeButton.addAction(UIAction { _ in onComplete() }, for: .touchUpInside)
        completeButton.translatesAutoresizingMaskIntoConstraints = false
        completeButton.setContentHuggingPriority(.required, for: .horizontal)
        completeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        for symbol in symbols {
            let button = accessoryButton(title: symbol, systemImage: nil, tint: .label)
            button.addAction(UIAction { _ in onInsert(symbol) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        let doneButton = accessoryButton(
            title: nil,
            systemImage: "keyboard.chevron.compact.down",
            tint: .systemBlue,
            accessibilityLabel: "Hide keyboard"
        )
        doneButton.addAction(UIAction { _ in onDismiss() }, for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        let leadingSeparator = UIView()
        leadingSeparator.backgroundColor = .separator
        leadingSeparator.translatesAutoresizingMaskIntoConstraints = false

        let trailingSeparator = UIView()
        trailingSeparator.backgroundColor = .separator
        trailingSeparator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(completeButton)
        addSubview(leadingSeparator)
        addSubview(scrollView)
        addSubview(trailingSeparator)
        addSubview(doneButton)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            completeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            completeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            completeButton.heightAnchor.constraint(equalToConstant: 36),
            completeButton.widthAnchor.constraint(equalToConstant: 42),
            leadingSeparator.leadingAnchor.constraint(equalTo: completeButton.trailingAnchor, constant: 5),
            leadingSeparator.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            leadingSeparator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            leadingSeparator.widthAnchor.constraint(equalToConstant: 1),
            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            doneButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: 36),
            doneButton.widthAnchor.constraint(equalToConstant: 42),
            trailingSeparator.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -5),
            trailingSeparator.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            trailingSeparator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            trailingSeparator.widthAnchor.constraint(equalToConstant: 1),
            scrollView.leadingAnchor.constraint(equalTo: leadingSeparator.trailingAnchor, constant: 5),
            scrollView.trailingAnchor.constraint(equalTo: trailingSeparator.leadingAnchor, constant: -5),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Keeps the key honest when the setting or the device's eligibility
    /// changes while the keyboard is already on screen.
    func setUsesAppleIntelligence(_ usesAppleIntelligence: Bool) {
        Self.applyAssistantAppearance(
            to: completeButton,
            usesAppleIntelligence: usesAppleIntelligence
        )
    }

    private static func assistantButton(usesAppleIntelligence: Bool) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.imagePadding = 4
        configuration.cornerStyle = .small
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 5, leading: 9, bottom: 5, trailing: 9
        )
        let button = UIButton(configuration: configuration)
        applyAssistantAppearance(to: button, usesAppleIntelligence: usesAppleIntelligence)
        return button
    }

    /// Apple Intelligence's sparkle only when Apple Intelligence will answer.
    /// Otherwise the same key completes Rust from the offline model, and says
    /// so with a plain code glyph rather than borrowing a promise.
    private static func applyAssistantAppearance(
        to button: UIButton,
        usesAppleIntelligence: Bool
    ) {
        var configuration = button.configuration ?? UIButton.Configuration.gray()
        configuration.image = UIImage(
            systemName: usesAppleIntelligence ? "sparkles" : "curlybraces"
        )
        configuration.baseForegroundColor = usesAppleIntelligence ? .systemBlue : .label
        button.configuration = configuration
        button.accessibilityLabel = usesAppleIntelligence
            ? "Complete Rust code with Apple Intelligence"
            : "Complete Rust code offline"
    }

    private func accessoryButton(
        title: String?,
        systemImage: String?,
        tint: UIColor,
        accessibilityLabel: String? = nil
    ) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.image = systemImage.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = 4
        configuration.baseForegroundColor = tint
        configuration.cornerStyle = .small
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)
        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        button.accessibilityLabel = accessibilityLabel ?? title
        return button
    }
}
