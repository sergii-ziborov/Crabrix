import XCTest
@testable import Crabrix

final class CodeContributionTests: XCTestCase {
    func testAnUntouchedProjectMeasuresNoChange() {
        let files = ["main.rs": "fn main() {}\n"]
        let contribution = CodeContribution.measure(previous: files, current: files)
        XCTAssertEqual(contribution.changedLines, 0)
    }

    func testRerunningUntouchedCodeEarnsFarLessThanEditingIt() {
        let files = ["main.rs": "fn main() {}\n"]
        let untouched = CodeContribution.measure(previous: files, current: files)
        let edited = CodeContribution.measure(
            previous: files,
            current: ["main.rs": "fn main() {\n    println!(\"hi\");\n}\n"]
        )
        // The whole point of the change: tapping Run again is not work.
        XCTAssertLessThan(untouched.points, edited.points)
        XCTAssertGreaterThan(untouched.points, 0, "a run still counts for something")
    }

    func testAddedAndRemovedLinesAreCountedSeparately() {
        let contribution = CodeContribution.measure(
            previous: ["main.rs": "a\nb\nc\n"],
            current: ["main.rs": "a\nx\ny\nc\n"]
        )
        XCTAssertEqual(contribution.addedLines, 2, "x and y are new")
        XCTAssertEqual(contribution.removedLines, 1, "b is gone")
    }

    func testANewFileCountsAsItsWholeContent() {
        let contribution = CodeContribution.measure(
            previous: ["main.rs": "fn main() {}"],
            current: ["main.rs": "fn main() {}", "lib.rs": "pub fn a() {}\npub fn b() {}"]
        )
        XCTAssertEqual(contribution.newFiles, 1)
        XCTAssertEqual(contribution.addedLines, 2)
    }

    func testADeletedFileStillCountsAsWork() {
        let contribution = CodeContribution.measure(
            previous: ["main.rs": "a\nb", "old.rs": "x\ny\nz"],
            current: ["main.rs": "a\nb"]
        )
        XCTAssertEqual(contribution.removedLines, 3)
    }

    func testTheFirstRunOfAProjectIsMarked() {
        let contribution = CodeContribution.measure(
            previous: [:],
            current: ["main.rs": "fn main() {}"]
        )
        XCTAssertTrue(contribution.isFirstRun)
        XCTAssertEqual(contribution.newFiles, 1)
    }

    func testPointsGrowWithTheSizeOfTheChangeButStayBounded() {
        let small = CodeContribution(addedLines: 5)
        let medium = CodeContribution(addedLines: 60)
        let huge = CodeContribution(addedLines: 50_000)
        XCTAssertLessThan(small.points, medium.points)
        XCTAssertLessThan(medium.points, huge.points)
        // A giant paste must not out-earn finishing a lesson many times over.
        XCTAssertLessThanOrEqual(huge.points, 150)
    }

    func testDiffIgnoresUnchangedSurroundingLines() {
        let before = ["fn main() {", "    let a = 1;", "}"].map { Substring($0) }
        let after = ["fn main() {", "    let a = 2;", "}"].map { Substring($0) }
        let diff = CodeContribution.lineDiff(from: before, to: after)
        XCTAssertEqual(diff.added, 1)
        XCTAssertEqual(diff.removed, 1)
    }

    func testAVeryLargeFileStillProducesAMeasurement() {
        // Past the LCS size guard it falls back to a multiset comparison, which
        // still has to report the right magnitude rather than giving up.
        let before = (0..<3_000).map { Substring("line \($0)") }
        var after = before
        after.append(contentsOf: (0..<40).map { Substring("extra \($0)") })
        let diff = CodeContribution.lineDiff(from: before, to: after)
        XCTAssertEqual(diff.added, 40)
        XCTAssertEqual(diff.removed, 0)
    }
}

final class CodeContributionLedgerTests: XCTestCase {
    private func makeLedger() -> (CodeContributionLedger, String) {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        return (CodeContributionLedger(defaults: UserDefaults(suiteName: suite)!), suite)
    }

    func testTheSecondRunIsMeasuredAgainstTheFirst() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let first = ledger.record(project: "demo", files: ["main.rs": "a\nb\n"])
        XCTAssertTrue(first.isFirstRun)

        let second = ledger.record(project: "demo", files: ["main.rs": "a\nb\n"])
        XCTAssertEqual(second.changedLines, 0, "nothing changed between the runs")

        let third = ledger.record(project: "demo", files: ["main.rs": "a\nb\nc\n"])
        XCTAssertEqual(third.addedLines, 1)
    }

    func testProjectsAreMeasuredIndependently() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        _ = ledger.record(project: "one", files: ["main.rs": "a\n"])
        let other = ledger.record(project: "two", files: ["main.rs": "a\n"])
        XCTAssertTrue(other.isFirstRun, "a different project starts from scratch")
    }
}
