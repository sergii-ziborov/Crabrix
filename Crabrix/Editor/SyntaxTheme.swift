import SwiftUI
import UIKit

/// One source of truth for token colours, shared by the editor and by every
/// place that shows a code sample — lesson briefs included, so a snippet in a
/// lesson looks exactly like the same code in the workspace.
enum SyntaxTheme {
    /// The surface code is drawn on, in both themes.
    ///
    /// Previously a flat `black.opacity(0.32)`, which over a white panel is a
    /// pale grey — so the light theme ended up with pale tokens on a pale
    /// background. Matching the editor's own surface keeps a snippet in a
    /// lesson looking like the same code in the workspace.
    static let background = adaptive(
        light: UIColor(red: 0.957, green: 0.969, blue: 0.984, alpha: 1),
        dark: UIColor(red: 0.035, green: 0.051, blue: 0.070, alpha: 1)
    )

    /// Token colours, per theme.
    ///
    /// The dark values are the original palette. The light ones are darker and
    /// more saturated because the same hue that reads well on near-black is
    /// unreadable on near-white — `println!` in lavender being the worst of
    /// them. `SyntaxContrastTests` measures every one of these against
    /// `background` in both themes rather than trusting the eye.
    static func color(for kind: SyntaxTokenKind) -> Color {
        switch kind {
        case .comment:
            adaptive(
                light: UIColor(red: 0.38, green: 0.43, blue: 0.50, alpha: 1),
                dark: UIColor(red: 0.53, green: 0.58, blue: 0.64, alpha: 1)
            )
        case .string:
            adaptive(
                light: UIColor(red: 0.02, green: 0.44, blue: 0.31, alpha: 1),
                dark: UIColor(red: 0.42, green: 0.83, blue: 0.66, alpha: 1)
            )
        case .keyword, .section:
            adaptive(
                light: UIColor(red: 0.72, green: 0.16, blue: 0.05, alpha: 1),
                dark: UIColor(red: 1.0, green: 0.39, blue: 0.27, alpha: 1)
            )
        case .type, .key:
            adaptive(
                light: UIColor(red: 0.06, green: 0.33, blue: 0.68, alpha: 1),
                dark: UIColor(red: 0.41, green: 0.70, blue: 1.0, alpha: 1)
            )
        case .number:
            adaptive(
                light: UIColor(red: 0.52, green: 0.34, blue: 0.02, alpha: 1),
                dark: UIColor(red: 0.95, green: 0.72, blue: 0.34, alpha: 1)
            )
        case .macro:
            adaptive(
                light: UIColor(red: 0.42, green: 0.16, blue: 0.70, alpha: 1),
                dark: UIColor(red: 0.79, green: 0.60, blue: 1.0, alpha: 1)
            )
        case .attribute:
            adaptive(
                light: UIColor(red: 0.65, green: 0.09, blue: 0.38, alpha: 1),
                dark: UIColor(red: 0.95, green: 0.54, blue: 0.75, alpha: 1)
            )
        }
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
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
        .background(SyntaxTheme.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).stroke(CrabrixTheme.border.opacity(0.7))
        }
        .accessibilityLabel("Code example")
        .accessibilityValue(code)
    }
}
