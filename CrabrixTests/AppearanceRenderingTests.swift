import SwiftUI
import UIKit
import XCTest
@testable import Crabrix

/// Render actual production components to artifacts without reading the Mac's
/// screen or substituting learner data. Contrast is checked separately.
@MainActor
final class AppearanceRenderingTests: XCTestCase {
    private let preference = "crabrix.appearance"

    func testCompactPickerFitsPhoneAndShowsAllChoicesAcrossIPadWidth() throws {
        let previous = UserDefaults.standard.object(forKey: preference)
        defer { UserDefaults.standard.set(previous, forKey: preference) }
        for appearance in [CrabrixAppearance.amberCircuit, .cyberpunk] {
            UserDefaults.standard.set(appearance.rawValue, forKey: preference)
            for width: CGFloat in [240, 313, 770] {
                let image = try render(
                    AppearancePicker(selection: .constant(appearance.rawValue)), width: width
                )
                XCTAssertEqual(image.size.width, width, accuracy: 1)
                XCTAssertGreaterThan(image.size.height, 44)
                XCTAssertLessThan(image.size.height, width >= 700 ? 100 : 280,
                                  "The selector should remain compact at \(width) points")
                attach(image, name: "picker-\(appearance.title)-\(Int(width))")
            }
        }
    }

    func testPickerAllowsLargeTextToGrowVertically() throws {
        let normal = try render(AppearancePicker(selection: .constant("system")), width: 313)
        let large = try render(AppearancePicker(selection: .constant("system"))
            .environment(\.dynamicTypeSize, .accessibility3), width: 313)
        XCTAssertEqual(large.size.width, normal.size.width, accuracy: 1)
        XCTAssertGreaterThan(large.size.height, normal.size.height)
        attach(large, name: "picker-accessibility3-313")
    }

    func testRenderRealAcademyHeroBannerAndCodeInBothCustomThemes() throws {
        let previous = UserDefaults.standard.object(forKey: preference)
        defer { UserDefaults.standard.set(previous, forKey: preference) }
        let unit = RustLearningUnit(
            id: "preview", level: 1, title: "Rust Foundations",
            subtitle: "Read, edit, compile, and trust rustc",
            lessons: (1...7).map {
                RustLesson(id: "preview-\($0)", title: "Rust", concept: "Source", minutes: 10, exercise: .runnable)
            }
        )
        for appearance in [CrabrixAppearance.amberCircuit, .cyberpunk] {
            UserDefaults.standard.set(appearance.rawValue, forKey: preference)
            let content = VStack(alignment: .leading, spacing: 20) {
                Text(appearance.title).font(.title2.bold())
                LearningHero(completedLessonCount: 7, totalLessonCount: 28,
                             actionTitle: "Continue course", actionSystemImage: "arrow.right",
                             theme: .basics, onAction: {})
                UnitBanner(unit: unit, palette: LearningPalette(
                    primary: RustCourseTheme.basics.primaryColor,
                    secondary: RustCourseTheme.basics.secondaryColor, symbol: "sparkles"
                ), completedCount: 7)
                Text("Variables").font(.headline)
                Text("let, mut, and shadowing").font(.caption).foregroundStyle(CrabrixTheme.muted)
                Text(SyntaxTheme.attributedString("// Change a binding explicitly\nlet mut score = 3;\nprintln!(\"score: {score}\");"))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SyntaxTheme.background)
            }
            .padding(20)
            let image = try render(content, width: 390)
            attach(image, name: "academy-\(appearance.title)-390")
        }
    }

    private func render<Content: View>(_ content: Content, width: CGFloat) throws -> UIImage {
        let renderer = ImageRenderer(content: content
            .foregroundStyle(CrabrixTheme.primary)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background(CrabrixTheme.background)
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage)
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
