import XCTest
import SwiftUI
import UIKit
@testable import Crabrix

/// Colour choices that have to survive both themes.
///
/// The locked lesson circle is nearly white in the light theme, so an icon
/// picked to sit on a dark background disappeared on it entirely. These tests
/// measure the contrast rather than trusting that it looks fine in dark mode.
@MainActor
final class ThemeContrastTests: XCTestCase {
    private func resolve(_ color: Color, style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    /// Relative luminance, per WCAG.
    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ first: UIColor, _ second: UIColor) -> CGFloat {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func testTheLockedLessonIconIsVisibleInBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            // The locked circle is a gradient from `raised` to `editor`; the
            // lighter end is the harder background to sit on.
            let background = resolve(CrabrixTheme.editor, style: style)
            let icon = resolve(CrabrixTheme.muted, style: style)
            let ratio = contrast(icon, background)
            XCTAssertGreaterThan(
                ratio, 3.0,
                "the lock is unreadable in \(style == .light ? "light" : "dark") mode at \(ratio)"
            )
        }
    }

    func testWhiteWouldHaveFailedInLightMode() {
        // Pins why the colour changed: the previous choice was invisible.
        let background = resolve(CrabrixTheme.editor, style: .light)
        let ratio = contrast(UIColor.white.withAlphaComponent(1), background)
        XCTAssertLessThan(ratio, 1.2, "white on a near-white circle is the bug this replaced")
    }

    func testPrimaryTextIsReadableOnEveryPanelInBothThemes() {
        let surfaces: [(String, Color)] = [
            ("background", CrabrixTheme.background),
            ("panel", CrabrixTheme.panel),
            ("raised", CrabrixTheme.raised),
            ("editor", CrabrixTheme.editor),
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, surface) in surfaces {
                let ratio = contrast(
                    resolve(CrabrixTheme.primary, style: style),
                    resolve(surface, style: style)
                )
                XCTAssertGreaterThan(
                    ratio, 7.0,
                    "primary text on \(name) is only \(ratio) in \(style == .light ? "light" : "dark")"
                )
            }
        }
    }

    func testMutedTextStaysLegibleOnEveryPanel() {
        let surfaces: [(String, Color)] = [
            ("background", CrabrixTheme.background),
            ("panel", CrabrixTheme.panel),
            ("raised", CrabrixTheme.raised),
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, surface) in surfaces {
                let ratio = contrast(
                    resolve(CrabrixTheme.muted, style: style),
                    resolve(surface, style: style)
                )
                // 4.5 is the WCAG AA threshold for body text.
                XCTAssertGreaterThan(
                    ratio, 4.5,
                    "muted text on \(name) is only \(ratio) in \(style == .light ? "light" : "dark")"
                )
            }
        }
    }
}

/// Syntax colours have to be readable on the surface code is drawn on, in both
/// themes. The palette was tuned for a dark background only, so in the light
/// theme `println!` in lavender on a pale block was effectively invisible.
@MainActor
final class SyntaxContrastTests: XCTestCase {
    private func resolve(_ color: Color, style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ first: UIColor, _ second: UIColor) -> CGFloat {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func testEveryTokenKindIsReadableInBothThemes() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let background = resolve(SyntaxTheme.background, style: style)
            for kind in SyntaxTokenKind.allCases {
                let ratio = contrast(resolve(SyntaxTheme.color(for: kind), style: style), background)
                XCTAssertGreaterThan(
                    ratio, 4.5,
                    "\(kind.rawValue) is only \(ratio) against the code background in "
                        + "\(style == .light ? "light" : "dark") mode"
                )
            }
        }
    }

    func testPlainCodeTextIsReadableOnTheCodeBackground() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrast(
                resolve(CrabrixTheme.primary, style: style),
                resolve(SyntaxTheme.background, style: style)
            )
            XCTAssertGreaterThan(ratio, 7.0, "unhighlighted code must be the most readable of all")
        }
    }

    func testTheOldFixedPaletteWouldHaveFailedInLightMode() {
        // Pins the bug this replaced: the previous macro colour on the previous
        // pale block. Both numbers are from the code as it was.
        let oldMacro = UIColor(red: 0.79, green: 0.60, blue: 1.0, alpha: 1)
        let oldBackground = UIColor(red: 0.68, green: 0.68, blue: 0.68, alpha: 1)
        XCTAssertLessThan(
            contrast(oldMacro, oldBackground), 2.0,
            "the old lavender on the old light-mode block is the bug being fixed"
        )
    }

    func testTokenColoursAreDistinctFromEachOtherInBothThemes() {
        // Highlighting only helps if the categories are tellable apart.
        for style in [UIUserInterfaceStyle.light, .dark] {
            let resolved = SyntaxTokenKind.allCases.map {
                resolve(SyntaxTheme.color(for: $0), style: style)
            }
            for (index, first) in resolved.enumerated() {
                for second in resolved[(index + 1)...] {
                    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
                    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
                    first.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
                    second.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
                    let distance = abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)
                    // Keyword/section and type/key deliberately share a colour.
                    XCTAssertTrue(
                        distance > 0.25 || distance == 0,
                        "two token colours are nearly the same in \(style == .light ? "light" : "dark")"
                    )
                }
            }
        }
    }
}
