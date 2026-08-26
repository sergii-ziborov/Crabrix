import SwiftUI
import UIKit

struct SyntaxCodeEditor: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("crabrix.editorFontSize") private var editorFontSize = 14.0
    @Binding var text: String
    @Binding var cursorOffset: Int
    let filePath: String
    let isEditable: Bool
    let onRequestCompletion: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = UIColor(CrabrixTheme.editor)
        textView.textColor = UIColor(CrabrixTheme.primary)
        textView.tintColor = UIColor(CrabrixTheme.blue)
        textView.keyboardAppearance = colorScheme == .dark ? .dark : .light
        textView.font = .monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 14, bottom: 16, right: 14)
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
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SyntaxCodeEditor
        var highlightedText = ""
        var highlightedFilePath = ""
        var highlightedFontSize = 0.0
        var highlightedColorScheme: ColorScheme?
        weak var textView: UITextView?
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
            title: "Complete",
            systemImage: "sparkles",
            tint: .systemBlue
        )
        completeButton.addAction(UIAction { _ in onComplete() }, for: .touchUpInside)
        stack.addArrangedSubview(completeButton)

        for symbol in symbols {
            let button = accessoryButton(title: symbol, systemImage: nil, tint: .label)
            button.addAction(UIAction { _ in onInsert(symbol) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        let doneButton = accessoryButton(
            title: "Done",
            systemImage: "keyboard.chevron.compact.down",
            tint: .systemBlue
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

    private func accessoryButton(title: String, systemImage: String?, tint: UIColor) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.image = systemImage.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = 4
        configuration.baseForegroundColor = tint
        configuration.cornerStyle = .small
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)
        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        button.accessibilityLabel = title
        return button
    }
}
