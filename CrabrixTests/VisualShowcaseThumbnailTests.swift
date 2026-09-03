import XCTest
@testable import Crabrix

final class VisualShowcaseThumbnailTests: XCTestCase {
    private var visualProjects: [RustShowcaseProject] {
        RustShowcaseLibrary.projects.filter(\.isVisual)
    }

    func testEveryVisualProjectHasAThumbnail() {
        for project in visualProjects {
            XCTAssertNotNil(
                VisualShowcaseArtwork.artwork(for: project.id),
                "\(project.id) shows a visual canvas but has no library preview"
            )
        }
        XCTAssertFalse(visualProjects.isEmpty)
    }

    /// The preview is a port of each project's own Rust. If someone edits the
    /// program's canvas header, this catches the preview drifting away from it.
    func testEachThumbnailMatchesTheCanvasItsProgramDeclares() throws {
        for project in visualProjects {
            let source = try XCTUnwrap(project.project.files["src/main.rs"], project.id)
            let artwork = try XCTUnwrap(
                VisualShowcaseArtwork.artwork(for: project.id),
                project.id
            )

            let declared = try XCTUnwrap(
                Self.canvasHeader(in: source),
                "\(project.id) has no CRABRIX_CANVAS header"
            )
            XCTAssertEqual(artwork.width, declared.width, project.id)
            XCTAssertEqual(artwork.height, declared.height, project.id)
            XCTAssertEqual(artwork.palette, declared.palette, project.id)
        }
    }

    func testEveryPixelIndexIsInsideItsPalette() throws {
        for project in visualProjects {
            let artwork = try XCTUnwrap(
                VisualShowcaseArtwork.artwork(for: project.id),
                project.id
            )
            XCTAssertEqual(
                artwork.indices.count, artwork.width * artwork.height, project.id
            )
            for index in artwork.indices {
                XCTAssertTrue(
                    (0..<artwork.palette.count).contains(index),
                    "\(project.id) uses palette index \(index) of \(artwork.palette.count)"
                )
            }
        }
    }

    func testTwoProjectsNeverShowTheSamePicture() {
        // The old thumbnail drew one hash-seeded grid for everything, so a
        // reader could not tell two canvases apart.
        let artworks = visualProjects.compactMap {
            VisualShowcaseArtwork.artwork(for: $0.id)
        }
        for (offset, artwork) in artworks.enumerated() {
            for other in artworks.dropFirst(offset + 1) {
                XCTAssertNotEqual(artwork, other)
            }
        }
    }

    // MARK: - Reading the program's own canvas header

    private static func canvasHeader(
        in source: String
    ) -> (width: Int, height: Int, palette: [String])? {
        guard let line = source
            .split(separator: "\n")
            .first(where: { $0.contains("CRABRIX_CANVAS:") })
        else { return nil }

        func number(_ key: String) -> Int? {
            guard let range = line.range(of: "\"\(key)\":") else { return nil }
            let digits = line[range.upperBound...].prefix { $0.isNumber }
            return Int(digits)
        }
        guard let width = number("width"), let height = number("height"),
              let paletteStart = line.range(of: "\"palette\":["),
              let paletteEnd = line[paletteStart.upperBound...].firstIndex(of: "]")
        else { return nil }

        let palette = line[paletteStart.upperBound..<paletteEnd]
            .components(separatedBy: ",")
            .map { $0.replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (width, height, palette)
    }
}
