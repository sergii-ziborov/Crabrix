import XCTest
@testable import Crabrix

final class BundledLicenseTests: XCTestCase {
    func testEveryDeclaredLicenceTextShipsInsideTheApp() {
        // Redistribution is the point: linking to a licence on the web is not
        // the same as including it, and Crabrix is meant to work offline.
        XCTAssertTrue(
            BundledLicenseCatalog.missingDocuments.isEmpty,
            "missing from the app bundle: \(BundledLicenseCatalog.missingDocuments)"
        )
    }

    func testTheRedistributedToolchainLicencesAreTheRealTexts() throws {
        let mit = try XCTUnwrap(BundledLicenseCatalog.text(forDocument: "Rust-LICENSE-MIT"))
        XCTAssertTrue(mit.contains("Permission is hereby granted, free of charge"))
        XCTAssertTrue(mit.contains("The Rust Project Contributors"))

        let apache = try XCTUnwrap(BundledLicenseCatalog.text(forDocument: "Rust-LICENSE-APACHE"))
        XCTAssertTrue(apache.contains("Apache License"))
        XCTAssertTrue(apache.contains("Version 2.0, January 2004"))
        // The Apache licence has to be complete, not an excerpt.
        XCTAssertTrue(apache.contains("END OF TERMS AND CONDITIONS"))

        let compiler = try XCTUnwrap(BundledLicenseCatalog.text(forDocument: "wasm-rustc-LICENSE"))
        XCTAssertTrue(compiler.contains("MIT License"))
    }

    func testEveryComponentNamesAtLeastOneDocument() {
        for license in BundledLicenseCatalog.all {
            XCTAssertFalse(license.documents.isEmpty, license.id)
            XCTAssertFalse(license.name.isEmpty, license.id)
            XCTAssertFalse(license.summary.isEmpty, license.id)
        }
        let ids = BundledLicenseCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "a component is listed twice")
    }

    func testTheNoticesFileIsAlsoBundled() {
        XCTAssertNotNil(LicensesView.load())
    }

    func testOfflineLegalDocumentsDecodeAndKeepTheAppWebsiteBoundary() throws {
        let documents = try BundledLegalDocuments.load()
        XCTAssertEqual(Set(documents.map(\.id)), ["about", "privacy", "terms", "source-license", "content-license"])
        let privacy = try XCTUnwrap(documents.first { $0.id == "privacy" })
        XCTAssertTrue(privacy.blocks.contains { $0.text.contains("Website Academy accounts") })
        XCTAssertTrue(privacy.blocks.contains { $0.text.contains("off-by-default Game Center") })
        let terms = try XCTUnwrap(documents.first { $0.id == "terms" })
        XCTAssertTrue(terms.blocks.contains { $0.text.contains("www.apple.com/legal/internet-services/itunes/dev/stdeula/") })
        for document in documents {
            XCTAssertFalse(document.blocks.isEmpty)
            XCTAssertEqual(document.sourceURL.scheme, "https")
            XCTAssertEqual(document.sourceURL.host, "crabrix.com")
        }
    }

    func testEveryInventoriedCompilerNoticeCanBeReadOffline() throws {
        let notices = try ToolchainNoticeCatalog.load()
        XCTAssertEqual(notices.count, 1594) // Primary group, supplemental group, 1592 source packages.
        for notice in notices {
            XCTAssertFalse(notice.documents.isEmpty, notice.name)
            for path in notice.documents {
                XCTAssertFalse(try ToolchainNoticeCatalog.text(archive: notice.archive, path: path).isEmpty, path)
            }
        }
    }
}
