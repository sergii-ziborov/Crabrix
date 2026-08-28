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
    let filePath: String
    let isEditable: Bool
    let diagnostics: [RustDiagnostic]
    let navigationTarget: EditorNavigationTarget?
    let onRequestCompletion: () -> Void

    init(
        text: Binding<String>,
        cursorOffset: Binding<Int>,
        filePath: String,
        isEditable: Bool,
        diagnostics: [RustDiagnostic] = [],
        navigationTarget: EditorNavigationTarget?,
        onRequestCompletion: @escaping () -> Void
    ) {
        _text = text
        _cursorOffset = cursorOffset
        self.filePath = filePath
        self.isEditable = isEditable
        self.diagnostics = diagnostics
        self.navigationTarget = navigationTarget
        self.onRequestCompletion = onRequestCompletion
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = RustSourceTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = UIColor(CrabrixTheme.editor)
        textView.textColor = UIColor(CrabrixTheme.primary)
        textView.tintColor = UIColor(CrabrixTheme.blue)
        textView.keyboardAppearance = colorScheme == .dark ? .dark : .light
        textView.font = .monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 54, bottom: 16, right: 14)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.alwaysBounceHorizontal = true
        textView.showsHorizontalScrollIndicator = true
        textView.disableLineWrapping()
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.accessibilityLabel = "Rust source editor"
        textView.lineNumberColor = UIColor(CrabrixTheme.muted).withAlphaComponent(0.82)
        textView.gutterSeparatorColor = UIColor(CrabrixTheme.border)
        textView.gutterBackgroundColor = UIColor(CrabrixTheme.editor)
        textView.text = text
        context.coordinator.textView = textView
        textView.inputAccessoryView = RustKeyboardAccessoryView(
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
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        textView.isEditable = isEditable
        textView.backgroundColor = UIColor(CrabrixTheme.editor)
        textView.keyboardAppearance = colorScheme == .dark ? .dark : .light
        if let sourceTextView = textView as? RustSourceTextView {
            sourceTextView.lineNumberColor = UIColor(CrabrixTheme.muted).withAlphaComponent(0.82)
            sourceTextView.gutterSeparatorColor = UIColor(CrabrixTheme.border)
            sourceTextView.gutterBackgroundColor = UIColor(CrabrixTheme.editor)
        }
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
            if !text.isEmpty {
                TypingLedger.shared.record(project: parent.filePath, inserted: text)
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            parent.text = textView.text
            parent.cursorOffset = textView.selectedRange.location
            applyHighlighting(to: textView, filePath: parent.filePath, preservingScroll: false)
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
            let offsetBefore = textView.contentOffset
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
            if preservingScroll, textView.contentOffset != offsetBefore {
                textView.contentOffset = offsetBefore
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
            textView.scrollRangeToVisible(lineRange)
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

private final class RustSourceTextView: UITextView {
    var lineNumberColor = UIColor.secondaryLabel {
        didSet { gutterView.lineNumberColor = lineNumberColor }
    }
    var gutterSeparatorColor = UIColor.separator {
        didSet { gutterView.separatorColor = gutterSeparatorColor }
    }
    var gutterBackgroundColor: UIColor = .clear {
        didSet { gutterView.backgroundColor = gutterBackgroundColor }
    }

    /// Width reserved for line numbers, matching `textContainerInset.left`.
    static let gutterWidth: CGFloat = 44

    /// The gutter is a subview rather than something drawn in `draw(_:)`.
    ///
    /// Drawing it inside the scroll view meant the code scrolled straight
    /// across the numbers: the left inset only reserves space at content x = 0,
    /// and that space scrolls away the moment you swipe sideways. A subview
    /// pinned to the visible left edge stays put and always draws above.
    private lazy var gutterView: GutterView = {
        let view = GutterView()
        view.isUserInteractionEnabled = false
        view.contentMode = .redraw
        view.backgroundColor = gutterBackgroundColor
        return view
    }()

    /// Set when the laid-out width may have changed, so `contentSize` is
    /// recomputed on the next layout pass instead of on every one.
    private var needsContentWidthUpdate = true

    override var text: String! {
        didSet { setNeedsContentWidthUpdate() }
    }

    override var font: UIFont? {
        didSet { setNeedsContentWidthUpdate() }
    }

    override var contentOffset: CGPoint {
        didSet { positionGutter() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // UITextView re-attaches the text container to its own width on every
        // layout pass, which silently turns wrapping back on. Code must scroll
        // sideways instead of wrapping, so the no-wrap setup is re-asserted here
        // rather than only once at construction.
        disableLineWrapping()

        if gutterView.superview !== self { addSubview(gutterView) }
        // Always the topmost subview: UITextView adds its own as it scrolls.
        if subviews.last !== gutterView { bringSubviewToFront(gutterView) }
        if let font {
            gutterView.numberFont = .monospacedDigitSystemFont(
                ofSize: max(font.pointSize - 3, 9),
                weight: .regular
            )
        }

        // Recomputing contentSize on every pass is what made a long file snap
        // back to line one: assigning it mid-scroll perturbs contentOffset, and
        // scrolling triggers another layout pass, so it never settled.
        if needsContentWidthUpdate || abs(contentSize.width - lastMeasuredWidth) > 0.5 {
            needsContentWidthUpdate = false
            growContentWidthToFitLongestLine()
        }

        positionGutter()
    }

    func setNeedsContentWidthUpdate() {
        needsContentWidthUpdate = true
        setNeedsLayout()
    }

    /// Keeps the gutter over the visible left edge and redraws its numbers.
    private func positionGutter() {
        guard gutterView.superview === self else { return }
        let frame = CGRect(
            x: contentOffset.x,
            y: contentOffset.y,
            width: Self.gutterWidth,
            height: bounds.height
        )
        if gutterView.frame != frame { gutterView.frame = frame }
        gutterView.verticalOffset = contentOffset.y
        gutterView.lines = visibleLineNumbers()
        gutterView.setNeedsDisplay()
    }

    private var lastMeasuredWidth: CGFloat = 0

    /// An unbounded text container stops wrapping, but it does not make the
    /// scroll view scrollable on its own: contentSize still has to cover the
    /// longest laid-out line.
    private func growContentWidthToFitLongestLine() {
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let required = ceil(used.maxX) + textContainerInset.left + textContainerInset.right
        let target = max(required, bounds.width)
        lastMeasuredWidth = target
        guard abs(contentSize.width - target) > 0.5 else { return }

        // Restore the reading position: shrinking the content can clamp the
        // offset, and the reader did not ask to be moved.
        let previous = contentOffset
        contentSize.width = target
        let maximumX = max(0, contentSize.width - bounds.width)
        let restored = CGPoint(x: min(previous.x, maximumX), y: previous.y)
        if contentOffset != restored { contentOffset = restored }
    }

    func disableLineWrapping() {
        if textContainer.widthTracksTextView {
            textContainer.widthTracksTextView = false
        }
        if textContainer.heightTracksTextView {
            textContainer.heightTracksTextView = false
        }
        if textContainer.lineBreakMode != .byClipping {
            textContainer.lineBreakMode = .byClipping
        }
        let unbounded = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if textContainer.size != unbounded {
            textContainer.size = unbounded
        }
    }

    /// The line numbers visible right now, with their y in content coordinates.
    private func visibleLineNumbers() -> [GutterView.Line] {
        let source = text ?? ""
        guard !source.isEmpty else {
            return [GutterView.Line(number: 1, y: textContainerInset.top)]
        }

        let lineStarts = logicalLineStarts(in: source)
        let visible = CGRect(
            x: contentOffset.x,
            y: contentOffset.y,
            width: bounds.width,
            height: bounds.height
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)

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

/// Draws the line numbers, pinned over the visible left edge of the editor.
///
/// Separate from the text view's own drawing on purpose: text rendering
/// composites over anything the scroll view draws itself once the content
/// scrolls sideways, which is what put code on top of the numbers.
private final class GutterView: UIView {
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

    init(
        onInsert: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
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

        let completeButton = accessoryButton(
            title: nil,
            systemImage: "sparkles",
            tint: .systemBlue,
            accessibilityLabel: "Complete Rust code"
        )
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
