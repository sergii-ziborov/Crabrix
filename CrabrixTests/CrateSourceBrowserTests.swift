import XCTest
@testable import Crabrix

/// Guideline 2.5.2 lets an app that teaches code download code, provided the
/// source stays fully viewable. These tests pin the part that makes it true.
final class CrateSourceBrowserTests: XCTestCase {
    private let version = SemanticVersion(major: 1, minor: 2, patch: 3)
    private var root: URL!

    override func setUpWithError() throws {
        root = try XCTUnwrap(
            CrateStorageLayout.sourceDirectory(name: "browsertest", version: version)
        )
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root.appending(path: "src"),
            withIntermediateDirectories: true
        )
        try "pub fn one() -> u32 { 1 }\n".write(
            to: root.appending(path: "src/lib.rs"), atomically: true, encoding: .utf8
        )
        try "pub mod helper;\n".write(
            to: root.appending(path: "src/helper.rs"), atomically: true, encoding: .utf8
        )
        try "[package]\nname = \"browsertest\"\n".write(
            to: root.appending(path: "Cargo.toml"), atomically: true, encoding: .utf8
        )
        try Data([0x00, 0xff, 0x80]).write(to: root.appending(path: "fixture.bin"))
        try FileManager.default.createDirectory(
            at: root.appending(path: ".cargo"),
            withIntermediateDirectories: true
        )
        try "[build]\ntarget = \"wasm32-wasip1\"\n".write(
            to: root.appending(path: ".cargo/config.toml"),
            atomically: true,
            encoding: .utf8
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testEveryExtractedFileIsListed() {
        let entries = CrateSourceBrowser.entries(name: "browsertest", version: version)
        let paths = Set(entries.map(\.path))
        // Not only the files the build compiles: everything that was extracted.
        XCTAssertEqual(
            paths,
            ["src/lib.rs", "src/helper.rs", ".cargo/config.toml", "Cargo.toml", "fixture.bin"]
        )
    }

    func testSourceFilesAreListedBeforeMetadata() {
        let entries = CrateSourceBrowser.entries(name: "browsertest", version: version)
        XCTAssertTrue(entries.first?.path.hasPrefix("src/") == true)
        XCTAssertEqual(entries.last?.path, "fixture.bin")
    }

    func testDeviceStyleAliasedRootKeepsMetadataPathsRelativeAndReadable() throws {
        let metadata = "{\"git\":{\"sha1\":\"test\"}}"
        try metadata.write(to: root.appending(path: ".cargo_vcs_info.json"), atomically: true, encoding: .utf8)
        let alias = FileManager.default.temporaryDirectory.appending(path: "crate-alias-\(UUID())")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: alias) }
        let canonical = root.resolvingSymlinksInPath()

        // /var vs /private/var on an iPhone is the same situation: the root
        // and enumerated child use different names for the same directory.
        XCTAssertEqual(CrateSourceBrowser.relativePath(
            of: canonical.appending(path: ".cargo_vcs_info.json"), in: alias
        ), ".cargo_vcs_info.json")
        XCTAssertEqual(Set(CrateSourceBrowser.entries(in: alias).map(\.path)), [
            "src/lib.rs", "src/helper.rs", ".cargo/config.toml", "Cargo.toml",
            "fixture.bin", ".cargo_vcs_info.json",
        ])
        XCTAssertNil(CrateSourceBrowser.sourceAccessIssue(in: alias))
        XCTAssertEqual(CrateSourceBrowser.contents(in: alias, path: ".cargo_vcs_info.json"), metadata)
        XCTAssertNotNil(CrateSourceBrowser.contents(in: alias, path: "src/lib.rs"))

        let before = CrateStore.sourceTreeEvidence(at: canonical)
        let after = CrateStore.sourceTreeEvidence(at: alias)
        XCTAssertEqual(before.fileCount, 6)
        XCTAssertEqual(after.fileCount, before.fileCount)
        XCTAssertEqual(after.expandedBytes, before.expandedBytes)
        XCTAssertEqual(after.sourceTreeHash, before.sourceTreeHash)
    }

    func testReadableSourceCannotFollowASymlinkOutsideItsCrate() throws {
        let outside = root.deletingLastPathComponent().appending(path: "outside-\(UUID()).rs")
        try "private source".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appending(path: "escape.rs"), withDestinationURL: outside)

        XCTAssertNil(CrateSourceBrowser.contents(in: root, path: "escape.rs"))
        XCTAssertNil(CrateSourceBrowser.contents(in: root, path: "../\(outside.lastPathComponent)"))
        XCTAssertNil(CrateSourceBrowser.relativePath(of: outside, in: root))
    }

    func testAFileCanBeReadBackAsText() {
        let text = CrateSourceBrowser.contents(
            name: "browsertest",
            version: version,
            path: "src/lib.rs"
        )
        XCTAssertEqual(text, "pub fn one() -> u32 { 1 }\n")
    }

    func testAPathCannotEscapeTheCrateDirectory() {
        // The paths come from `entries`, but a traversal must still be refused
        // rather than reading somewhere else in the container.
        XCTAssertNil(
            CrateSourceBrowser.contents(
                name: "browsertest",
                version: version,
                path: "../../../../etc/passwd"
            )
        )
    }

    func testAMissingCrateListsNothingRatherThanFailing() {
        XCTAssertTrue(
            CrateSourceBrowser.entries(name: "not-downloaded", version: version).isEmpty
        )
        XCTAssertNil(
            CrateSourceBrowser.contents(name: "not-downloaded", version: version, path: "src/lib.rs")
        )
    }

    func testSummaryCountsRustFiles() throws {
        let summary = try XCTUnwrap(CrateSourceBrowser.summary(name: "browsertest", version: version))
        XCTAssertTrue(summary.contains("5 files"), summary)
        XCTAssertTrue(summary.contains("2 Rust"), summary)
    }

    func testVendorAndEditCopiesEveryEditableSourceButNotBinaryAssets() throws {
        let files = try CrateSourceBrowser.vendorableFiles(
            name: "browsertest",
            version: version
        )

        XCTAssertEqual(files["Cargo.toml"], "[package]\nname = \"browsertest\"\n")
        XCTAssertEqual(files["src/lib.rs"], "pub fn one() -> u32 { 1 }\n")
        XCTAssertEqual(files["src/helper.rs"], "pub mod helper;\n")
        XCTAssertEqual(files[".cargo/config.toml"], "[build]\ntarget = \"wasm32-wasip1\"\n")
        XCTAssertNil(files["fixture.bin"])
    }

    func testOversizedProgrammingSourceFailsClosedBeforeBuildOrVendor() throws {
        let path = "src/oversized.rs"
        let byteCount = CrateSourceBrowser.maximumEditableSourceBytes + 1
        try Data(repeating: 0x20, count: byteCount).write(
            to: root.appending(path: path),
            options: .atomic
        )

        let expected = CrateSourceBrowser.SourceAccessIssue.sourceTooLarge(
            path: path,
            byteCount: byteCount,
            limit: CrateSourceBrowser.maximumEditableSourceBytes
        )
        XCTAssertEqual(
            CrateSourceBrowser.sourceAccessIssue(name: "browsertest", version: version),
            expected
        )
        XCTAssertThrowsError(
            try CrateSourceBrowser.vendorableFiles(name: "browsertest", version: version)
        ) { error in
            XCTAssertEqual(error as? CrateSourceBrowser.SourceAccessIssue, expected)
        }
    }

    func testInvalidUTF8ProgrammingSourceFailsClosed() throws {
        try Data([0xff, 0xfe, 0xfd]).write(to: root.appending(path: "src/not-utf8.rs"))

        XCTAssertEqual(
            CrateSourceBrowser.sourceAccessIssue(name: "browsertest", version: version),
            .sourceIsNotUTF8("src/not-utf8.rs")
        )
    }

    func testExplicitLibraryPathIsAuditedEvenWithoutRustExtension() throws {
        try """
        [package]
        name = "browsertest"
        version = "1.2.3"

        [lib]
        path = "src/generated.inc"
        """.write(
            to: root.appending(path: "Cargo.toml"),
            atomically: true,
            encoding: .utf8
        )
        let byteCount = CrateSourceBrowser.maximumEditableSourceBytes + 1
        try Data(repeating: 0x20, count: byteCount).write(
            to: root.appending(path: "src/generated.inc"),
            options: .atomic
        )

        XCTAssertEqual(
            CrateSourceBrowser.sourceAccessIssue(name: "browsertest", version: version),
            .sourceTooLarge(
                path: "src/generated.inc",
                byteCount: byteCount,
                limit: CrateSourceBrowser.maximumEditableSourceBytes
            )
        )
    }

    func testNonstandardIncludedSourceIsFullyEditable() throws {
        try "include!(concat!(\"../generated\", \".txt\"));".write(
            to: root.appending(path: "src/lib.rs"), atomically: true, encoding: .utf8
        )
        let source = "pub fn generated() -> u32 { 42 }"
        try source.write(to: root.appending(path: "generated.txt"), atomically: true, encoding: .utf8)
        XCTAssertNil(CrateSourceBrowser.sourceAccessIssue(in: root))
        XCTAssertEqual(
            try CrateSourceBrowser.vendorableFiles(name: "browsertest", version: version)["generated.txt"],
            source
        )
    }

    func testOversizedNonstandardSourceFailsBeforeBuildAndVendor() throws {
        try "#[path = \"../generated.data\"] mod generated;".write(
            to: root.appending(path: "src/lib.rs"), atomically: true, encoding: .utf8
        )
        let size = CrateSourceBrowser.maximumEditableSourceBytes + 1
        try Data(repeating: 0x20, count: size).write(to: root.appending(path: "generated.data"))
        XCTAssertEqual(CrateSourceBrowser.sourceAccessIssue(in: root), .sourceTooLarge(
            path: "generated.data", byteCount: size, limit: CrateSourceBrowser.maximumEditableSourceBytes
        ))
        XCTAssertThrowsError(try CrateSourceBrowser.vendorableFiles(name: "browsertest", version: version))
    }

    func testNonstandardTextFilesCannotBeSilentlyDroppedAtFileLimit() throws {
        for index in 0..<LocalProjectLoader.maximumFileCount {
            try "// Rust source".write(
                to: root.appending(path: "part-\(index).inc"), atomically: true, encoding: .utf8
            )
        }
        XCTAssertEqual(CrateSourceBrowser.sourceAccessIssue(in: root), .tooManySourceFiles(
            count: LocalProjectLoader.maximumFileCount + 4, limit: LocalProjectLoader.maximumFileCount
        ))
        XCTAssertThrowsError(try CrateSourceBrowser.vendorableFiles(name: "browsertest", version: version))
    }

    func testOversizedBinaryAssetDoesNotPretendToBeEditableSource() throws {
        try Data(
            repeating: 0xff,
            count: CrateSourceBrowser.maximumEditableSourceBytes + 1
        ).write(to: root.appending(path: "large-fixture.bin"), options: .atomic)

        XCTAssertNil(
            CrateSourceBrowser.sourceAccessIssue(name: "browsertest", version: version)
        )
        let files = try CrateSourceBrowser.vendorableFiles(
            name: "browsertest",
            version: version
        )
        XCTAssertNil(files["large-fixture.bin"])
        XCTAssertNotNil(files["src/lib.rs"])
    }
}

final class CrateGuideTests: XCTestCase {
    private let version = SemanticVersion(major: 2, minor: 0, patch: 1)
    private var root: URL!

    override func setUpWithError() throws {
        root = try XCTUnwrap(CrateStorageLayout.sourceDirectory(name: "guidetest", version: version))
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root.appending(path: "examples"),
            withIntermediateDirectories: true
        )
        try """
        [package]
        name = "guidetest"
        description = "A small crate for testing guides."
        license = "MIT OR Apache-2.0"
        keywords = ["testing", "guide"]
        repository = "https://github.com/example/guidetest"
        """.write(to: root.appending(path: "Cargo.toml"), atomically: true, encoding: .utf8)
        try "# guidetest\n\nUse it like this.\n".write(
            to: root.appending(path: "README.md"), atomically: true, encoding: .utf8
        )
        try "fn main() {}\n".write(
            to: root.appending(path: "examples/basic.rs"), atomically: true, encoding: .utf8
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDescriptionAndMetadataComeFromTheCratesOwnManifest() throws {
        let guide = try XCTUnwrap(CrateGuide.load(name: "guidetest", version: version))
        XCTAssertEqual(guide.summaryLine, "A small crate for testing guides.")
        XCTAssertEqual(guide.license, "MIT OR Apache-2.0")
        XCTAssertEqual(guide.keywords, ["testing", "guide"])
        XCTAssertEqual(guide.repository, "https://github.com/example/guidetest")
    }

    func testTheReadmeIsTheGuide() throws {
        let guide = try XCTUnwrap(CrateGuide.load(name: "guidetest", version: version))
        XCTAssertTrue(try XCTUnwrap(guide.readme).contains("Use it like this."))
        XCTAssertTrue(guide.hasAnything)
    }

    func testExamplesAreListed() throws {
        let guide = try XCTUnwrap(CrateGuide.load(name: "guidetest", version: version))
        XCTAssertEqual(guide.examples, ["examples/basic.rs"])
    }

    func testDocsRsIsOfferedEvenWithoutADocumentationKey() throws {
        let guide = try XCTUnwrap(CrateGuide.load(name: "guidetest", version: version))
        let labels = guide.links.map(\.label)
        XCTAssertTrue(labels.contains("Documentation"))
        XCTAssertTrue(labels.contains("crates.io"))
    }

    func testAnUndownloadedCrateHasNoGuide() {
        XCTAssertNil(CrateGuide.load(name: "never-fetched", version: version))
    }
}

final class MarkdownRendererTests: XCTestCase {
    func testHeadingsListsAndCodeBecomeSeparateBlocks() {
        let blocks = MarkdownRenderer.blocks(of: """
        # Title

        Some text.

        - one
        - two

        ```rust
        fn main() {}
        ```
        """)
        XCTAssertTrue(blocks.contains(.heading(level: 1, text: "Title")))
        XCTAssertTrue(blocks.contains(.bullet("one")))
        XCTAssertTrue(blocks.contains(.code("fn main() {}")))
    }

    func testCodeInsideAFenceIsNotTreatedAsMarkdown() {
        // A '# comment' inside Rust must stay code, not become a heading.
        let blocks = MarkdownRenderer.blocks(of: """
        ```
        # not a heading
        - not a bullet
        ```
        """)
        XCTAssertEqual(blocks, [.code("# not a heading\n- not a bullet")])
    }

    func testAnUnterminatedFenceStillRenders() {
        let blocks = MarkdownRenderer.blocks(of: "```\nfn main() {}")
        XCTAssertEqual(blocks, [.code("fn main() {}")])
    }

    func testAVeryLongReadmeIsTruncatedRatherThanLaidOutInFull() {
        let huge = String(repeating: "word ", count: 40_000)
        let rendered = MarkdownRenderer.attributed(huge)
        XCTAssertLessThan(
            String(rendered.characters).count,
            MarkdownRenderer.maximumCharacters + 100
        )
    }

    func testParagraphsSurviveWithTheirInlineFormatting() {
        let rendered = MarkdownRenderer.attributed("Use **bold** and `code`.")
        let text = String(rendered.characters)
        XCTAssertTrue(text.contains("bold"))
        XCTAssertTrue(text.contains("code"))
        XCTAssertFalse(text.contains("**"), "inline markdown should be interpreted, not shown")
    }
}
