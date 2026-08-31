import XCTest
@testable import Crabrix

final class SemanticVersionTests: XCTestCase {
    private func version(_ text: String) -> SemanticVersion {
        guard let value = SemanticVersion(text) else {
            XCTFail("\(text) is not a version")
            return SemanticVersion(major: 0, minor: 0, patch: 0)
        }
        return value
    }

    func testParsesAndOrdersVersions() {
        XCTAssertEqual(version("1.2.3").description, "1.2.3")
        XCTAssertEqual(version("1.2").description, "1.2.0")
        XCTAssertEqual(version("1").description, "1.0.0")
        XCTAssertEqual(version("0.11.0-beta.2").prerelease, ["beta", "2"])
        XCTAssertNil(SemanticVersion("not-a-version"))

        // A prerelease sorts below its release, and numeric identifiers sort
        // numerically rather than as text.
        XCTAssertLessThan(version("1.0.0-alpha"), version("1.0.0"))
        XCTAssertLessThan(version("1.0.0-alpha.2"), version("1.0.0-alpha.10"))
        XCTAssertLessThan(version("1.0.0-alpha"), version("1.0.0-beta"))
        XCTAssertLessThan(version("1.9.0"), version("1.10.0"))
        XCTAssertEqual(
            [version("2.0.0"), version("1.0.0"), version("1.5.2")].max(),
            version("2.0.0")
        )
    }

    func testCaretRequirementsFollowCargoZeroRules() throws {
        func matches(_ requirement: String, _ candidate: String) -> Bool {
            VersionRequirement(requirement)?.isSatisfied(by: version(candidate)) ?? false
        }

        XCTAssertTrue(matches("1", "1.9.9"))
        XCTAssertFalse(matches("1", "2.0.0"))
        XCTAssertTrue(matches("^1.2.3", "1.2.4"))
        XCTAssertFalse(matches("^1.2.3", "1.2.2"))
        // ^0.2.3 may not cross the minor boundary.
        XCTAssertTrue(matches("0.2.3", "0.2.9"))
        XCTAssertFalse(matches("0.2.3", "0.3.0"))
        // ^0.0.3 is compatible only with itself.
        XCTAssertTrue(matches("0.0.3", "0.0.3"))
        XCTAssertFalse(matches("0.0.3", "0.0.4"))
    }

    func testTildeExactWildcardAndRangeRequirements() {
        func matches(_ requirement: String, _ candidate: String) -> Bool {
            VersionRequirement(requirement)?.isSatisfied(by: version(candidate)) ?? false
        }

        XCTAssertTrue(matches("~1.2.3", "1.2.9"))
        XCTAssertFalse(matches("~1.2.3", "1.3.0"))
        XCTAssertTrue(matches("~1", "1.7.0"))
        XCTAssertTrue(matches("=1.0.229", "1.0.229"))
        XCTAssertFalse(matches("=1.0.229", "1.0.230"))
        XCTAssertTrue(matches("*", "9.9.9"))
        XCTAssertTrue(matches("1.*", "1.4.0"))
        XCTAssertFalse(matches("1.*", "2.0.0"))
        XCTAssertTrue(matches("1.2.*", "1.2.99"))
        XCTAssertFalse(matches("1.2.*", "1.3.0"))
        XCTAssertTrue(matches(">=1.2, <1.5", "1.4.9"))
        XCTAssertFalse(matches(">=1.2, <1.5", "1.5.0"))
    }

    func testCargoWildcardMatrixUsesTheWildcardBoundary() {
        func matches(_ requirement: String, _ candidate: String) -> Bool {
            VersionRequirement(requirement)?.isSatisfied(by: version(candidate)) ?? false
        }

        XCTAssertTrue(matches("*", "0.0.0"))
        XCTAssertTrue(matches("1.*", "1.99.99"))
        XCTAssertFalse(matches("1.*", "2.0.0"))
        XCTAssertTrue(matches("1.x", "1.8.0"))
        XCTAssertFalse(matches("1.x", "2.0.0"))
        XCTAssertTrue(matches("1.2.*", "1.2.99"))
        XCTAssertFalse(matches("1.2.*", "1.3.0"))
        XCTAssertTrue(matches("1.2.x", "1.2.7"))
        XCTAssertFalse(matches("1.2.x", "1.3.0"))
        XCTAssertTrue(matches("0.*", "0.99.0"))
        XCTAssertFalse(matches("0.*", "1.0.0"))
        XCTAssertTrue(matches("0.2.*", "0.2.99"))
        XCTAssertFalse(matches("0.2.*", "0.3.0"))
    }

    func testMalformedOrOperatorPrefixedWildcardsAreRejected() {
        XCTAssertNil(VersionRequirement("1.*.3"))
        XCTAssertNil(VersionRequirement("*.1"))
        XCTAssertNil(VersionRequirement("1.x.2"))
        XCTAssertNil(VersionRequirement("^1.2.*"))
        XCTAssertNil(VersionRequirement("~1.*"))
        XCTAssertNil(VersionRequirement("=1.*"))
    }

    func testPrereleasesOnlyMatchWhenExplicitlyRequested() {
        let stable = VersionRequirement("1.0.0")
        XCTAssertFalse(stable?.isSatisfied(by: version("1.5.0-beta.1")) ?? true)

        let opted = VersionRequirement("1.5.0-beta.1")
        XCTAssertTrue(opted?.isSatisfied(by: version("1.5.0-beta.2")) ?? false)
        XCTAssertFalse(opted?.isSatisfied(by: version("1.6.0-beta.1")) ?? true)
    }

    func testBestMatchPicksTheHighestSatisfyingVersion() {
        let candidates = ["1.0.0", "1.4.2", "1.9.0", "2.0.0"].map(version)
        XCTAssertEqual(VersionRequirement("^1")?.bestMatch(in: candidates), version("1.9.0"))
        XCTAssertEqual(VersionRequirement("*")?.bestMatch(in: candidates), version("2.0.0"))
        XCTAssertNil(VersionRequirement("^3")?.bestMatch(in: candidates))
    }

    func testCaretCompatibilityBuckets() {
        XCTAssertTrue(version("1.2.0").isCaretCompatible(with: version("1.9.0")))
        XCTAssertFalse(version("1.2.0").isCaretCompatible(with: version("2.0.0")))
        XCTAssertTrue(version("0.4.1").isCaretCompatible(with: version("0.4.9")))
        XCTAssertFalse(version("0.4.1").isCaretCompatible(with: version("0.5.0")))
    }
}
