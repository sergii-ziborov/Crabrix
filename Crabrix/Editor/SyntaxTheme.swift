import SwiftUI
import UIKit

/// One source of truth for token colours, shared by the editor and by every
/// place that shows a code sample — lesson briefs included, so a snippet in a
/// lesson looks exactly like the same code in the workspace.
enum SyntaxTheme {
    static func color(for kind: SyntaxTokenKind) -> Color {
        switch kind {
        case .comment: CrabrixTheme.muted
        case .string: CrabrixTheme.mint
        case .keyword: CrabrixTheme.coral
        case .type: CrabrixTheme.blue
        case .number: CrabrixTheme.amber
        case .macro: Color(red: 0.79, green: 0.60, blue: 1.0)
        case .attribute: Color(red: 0.95, green: 0.54, blue: 0.75)
        case .section: CrabrixTheme.coral
        case .key: CrabrixTheme.blue
        }
    }

    static func uiColor(for kind: SyntaxTokenKind) -> UIColor {
        UIColor(color(for: kind))
    }

    /// Highlights `code` for display outside the editable text view.
    static func attributedString(
        _ code: String,
        filePath: String = "snippet.rs",
        fontSize: CGFloat = 13
    ) -> AttributedString {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attributed = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: font,
                .foregroundColor: UIColor(CrabrixTheme.primary),
            ]
        )
        let length = attributed.length
        for token in SyntaxHighlighter.tokens(in: code, filePath: filePath) {
            guard NSMaxRange(token.range) <= length else { continue }
            attributed.addAttribute(
                .foregroundColor,
                value: uiColor(for: token.kind),
                range: token.range
            )
        }
        return AttributedString(attributed)
    }
}

/// A read-only, syntax-highlighted code sample.
struct HighlightedCodeBlock: View {
    let code: String
    var filePath: String = "snippet.rs"
    var fontSize: CGFloat = 13

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(SyntaxTheme.attributedString(code, filePath: filePath, fontSize: fontSize))
                .textSelection(.enabled)
                // Ideal size in both axes. Horizontal keeps long lines from
                // wrapping; vertical is what stops a long snippet being
                // squeezed to the height of its container, which silently
                // truncated everything below the first screenful.
                .fixedSize(horizontal: true, vertical: true)
                .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).stroke(CrabrixTheme.border.opacity(0.7))
        }
        .accessibilityLabel("Code example")
        .accessibilityValue(code)
    }
}
