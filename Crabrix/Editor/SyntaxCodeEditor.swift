import SwiftUI
import UIKit

struct SyntaxCodeEditor: UIViewRepresentable {
    @Binding var text: String
    let filePath: String
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = UIColor(CrabrixTheme.editor)
        textView.textColor = .white
        textView.tintColor = UIColor(CrabrixTheme.blue)
        textView.keyboardAppearance = .dark
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
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
        context.coordinator.applyHighlighting(to: textView, filePath: filePath)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        textView.isEditable = isEditable
        if textView.text != text {
            let selection = textView.selectedRange
            textView.text = text
            textView.selectedRange = NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            )
        }
        if context.coordinator.highlightedText != text
            || context.coordinator.highlightedFilePath != filePath {
            context.coordinator.applyHighlighting(to: textView, filePath: filePath)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SyntaxCodeEditor
        var highlightedText = ""
        var highlightedFilePath = ""
        private var isApplyingHighlight = false

        init(parent: SyntaxCodeEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            parent.text = textView.text
            applyHighlighting(to: textView, filePath: parent.filePath)
        }

        func applyHighlighting(to textView: UITextView, filePath: String) {
            let source = textView.text ?? ""
            let fullRange = NSRange(location: 0, length: (source as NSString).length)
            let selection = textView.selectedRange
            let baseFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            let base: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: UIColor.white,
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
