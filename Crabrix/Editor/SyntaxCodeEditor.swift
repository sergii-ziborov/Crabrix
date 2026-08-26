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
    let navigationTarget: EditorNavigationTarget?
    let onRequestCompletion: () -> Void

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
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.accessibilityLabel = "Rust source editor"
        textView.lineNumberColor = UIColor(CrabrixTheme.muted).withAlphaComponent(0.82)
        textView.gutterSeparatorColor = UIColor(CrabrixTheme.border)
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
            || context.coordinator.highlightedColorScheme != colorScheme {
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
        weak var textView: UITextView?
        var lastNavigationID: UUID?
        private var isApplyingHighlight = false

        init(parent: SyntaxCodeEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            parent.text = textView.text
            parent.cursorOffset = textView.selectedRange.location
            applyHighlighting(to: textView, filePath: parent.filePath)
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
            applyHighlighting(to: textView, filePath: parent.filePath)
        }

        func applyHighlighting(to textView: UITextView, filePath: String) {
            let source = textView.text ?? ""
            let fullRange = NSRange(location: 0, length: (source as NSString).length)
            let selection = textView.selectedRange
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
            textView.textStorage.endEditing()
            textView.typingAttributes = base
            textView.selectedRange = selection
            isApplyingHighlight = false
            highlightedText = source
            highlightedFilePath = filePath
            highlightedFontSize = parent.editorFontSize
            highlightedColorScheme = parent.colorScheme
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

        private func color(for kind: SyntaxTokenKind) -> UIColor {
            switch kind {
            case .comment: UIColor(CrabrixTheme.muted)
            case .string: UIColor(CrabrixTheme.mint)
            case .keyword: UIColor(CrabrixTheme.coral)
            case .type: UIColor(CrabrixTheme.blue)
            case .number: UIColor(CrabrixTheme.amber)
            case .macro: UIColor(red: 0.79, green: 0.60, blue: 1.0, alpha: 1)
            case .attribute: UIColor(red: 0.95, green: 0.54, blue: 0.75, alpha: 1)
            case .section: UIColor(CrabrixTheme.coral)
            case .key: UIColor(CrabrixTheme.blue)
            }
        }
    }
}

private final class RustSourceTextView: UITextView {
    var lineNumberColor = UIColor.secondaryLabel { didSet { setNeedsDisplay() } }
    var gutterSeparatorColor = UIColor.separator { didSet { setNeedsDisplay() } }

    override var text: String! {
        didSet { setNeedsDisplay() }
    }

    override var contentOffset: CGPoint {
        didSet { setNeedsDisplay() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        drawLineNumbers()
    }

    private func drawLineNumbers() {
        guard let font else { return }
        let source = text ?? ""
        let lineStarts = logicalLineStarts(in: source)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: max(font.pointSize - 3, 9), weight: .regular),
            .foregroundColor: lineNumberColor,
        ]
        let gutterX = bounds.minX
        let gutterWidth: CGFloat = 44

        let separator = UIBezierPath()
        separator.move(to: CGPoint(x: gutterX + gutterWidth, y: bounds.minY))
        separator.addLine(to: CGPoint(x: gutterX + gutterWidth, y: bounds.maxY))
        gutterSeparatorColor.setStroke()
        separator.lineWidth = 1 / max(UIScreen.main.scale, 1)
        separator.stroke()

        guard !source.isEmpty else {
            drawLineNumber(1, y: textContainerInset.top, gutterX: gutterX, width: gutterWidth, attributes: attributes)
            return
        }

        let visible = CGRect(
            x: contentOffset.x,
            y: contentOffset.y,
            width: bounds.width,
            height: bounds.height
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        var drawnLines: Set<Int> = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] rect, _, _, glyphRange, _ in
            guard let self, glyphRange.location < self.layoutManager.numberOfGlyphs else { return }
            let characterIndex = self.layoutManager.characterIndexForGlyph(at: glyphRange.location)
            let line = self.lineNumber(at: characterIndex, starts: lineStarts)
            guard drawnLines.insert(line).inserted else { return }
            let y = rect.minY + self.textContainerInset.top
            self.drawLineNumber(line, y: y, gutterX: gutterX, width: gutterWidth, attributes: attributes)
        }
    }

    private func drawLineNumber(
        _ line: Int,
        y: CGFloat,
        gutterX: CGFloat,
        width: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let value = "\(line)" as NSString
        let size = value.size(withAttributes: attributes)
        value.draw(
            at: CGPoint(x: gutterX + width - size.width - 8, y: y),
            withAttributes: attributes
        )
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
        stack.addArrangedSubview(completeButton)

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

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(separator)
        addSubview(doneButton)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            doneButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: 36),
            doneButton.widthAnchor.constraint(equalToConstant: 42),
            separator.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -5),
            separator.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            separator.widthAnchor.constraint(equalToConstant: 1),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: separator.leadingAnchor, constant: -5),
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
