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
