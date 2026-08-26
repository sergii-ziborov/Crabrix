import XCTest
@testable import Crabrix

final class GitHubRepositoryReferenceTests: XCTestCase {
    func testParsesRepositoryAndNestedBranchReference() throws {
        let reference = try GitHubRepositoryReference.parse(
            "https://github.com/owner/repository/tree/feature/compiler"
        )

        XCTAssertEqual(reference.owner, "owner")
        XCTAssertEqual(reference.repository, "repository")
        XCTAssertEqual(reference.reference, "feature/compiler")
        XCTAssertEqual(
            reference.archiveURL.absoluteString,
            "https://github.com/owner/repository/archive/feature/compiler.zip"
        )
    }

    func testAcceptsGitSuffixAndURLWithoutScheme() throws {
        let reference = try GitHubRepositoryReference.parse("github.com/crabrix/app.git")
        XCTAssertEqual(reference.repository, "app")
        XCTAssertEqual(reference.reference, nil)
        XCTAssertTrue(reference.archiveURL.absoluteString.hasSuffix("/archive/HEAD.zip"))
    }

    func testRejectsNonGitHubHost() {
        XCTAssertThrowsError(try GitHubRepositoryReference.parse("https://example.com/owner/repo"))
    }
}
