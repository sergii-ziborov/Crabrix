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

    func testAFileRememberedOnlyByDigestIsNotMistakenForNewWork() {
        let text = (0..<500).map { "let value\($0) = \($0);" }.joined(separator: "\n")
        let baseline = ["src/big.rs": FileBaseline(text: text).withoutText]

        let untouched = CodeContribution.measure(
            baseline: baseline,
            current: ["src/big.rs": text]
        )
        XCTAssertEqual(untouched.changedLines, 0, "the digest says it did not change")
        XCTAssertEqual(untouched.newFiles, 0, "a file we still remember is not new")

        let edited = CodeContribution.measure(
            baseline: baseline,
            current: ["src/big.rs": text + "\nlet extra = 1;"]
        )
        XCTAssertEqual(edited.addedLines, 1)
        XCTAssertEqual(edited.newFiles, 0)
    }

    func testAnInPlaceEditOfAForgottenFileStillCountsAsWork() {
        let before = "let a = 1;\nlet b = 2;"
        let baseline = ["src/lib.rs": FileBaseline(text: before).withoutText]
        let changed = CodeContribution.measure(
            baseline: baseline,
            current: ["src/lib.rs": "let a = 9;\nlet b = 2;"]
        )
        // The line count did not move, so the estimate is deliberately small,
        // but calling it unchanged would be wrong.
        XCTAssertEqual(changed.changedLines, 1)
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
        let projectID = UUID()

        let first = ledger.record(projectID: projectID, files: ["main.rs": "a\nb\n"])
        XCTAssertTrue(first.isFirstRun)

        let second = ledger.record(projectID: projectID, files: ["main.rs": "a\nb\n"])
        XCTAssertEqual(second.changedLines, 0, "nothing changed between the runs")

        let third = ledger.record(projectID: projectID, files: ["main.rs": "a\nb\nc\n"])
        XCTAssertEqual(third.addedLines, 1)
    }

    func testALargeUntouchedFileIsNotRescoredOnEveryRun() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let projectID = UUID()
        // Past the per-project snapshot budget, so the ledger has to forget
        // this file's text and keep only its identity.
        let big = (0..<40_000).map { "let value\($0) = \($0);" }.joined(separator: "\n")
        let files = ["src/big.rs": big, "src/main.rs": "fn main() {}\n"]

        XCTAssertTrue(ledger.record(projectID: projectID, files: files).isFirstRun)

        let rerun = ledger.record(projectID: projectID, files: files)
        XCTAssertEqual(rerun.changedLines, 0, "nothing was written between the runs")
        XCTAssertEqual(rerun.newFiles, 0, "the file was remembered, not dropped")

        let edited = ledger.record(
            projectID: projectID,
            files: ["src/big.rs": big + "\nlet extra = 1;", "src/main.rs": "fn main() {}\n"]
        )
        XCTAssertEqual(edited.addedLines, 1)
    }

    func testABaselineWrittenByAnOlderBuildIsKeptRatherThanDiscarded() {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let projectID = UUID()

        // The pre-digest shape, as an earlier release wrote it.
        let legacy = """
        {"\(projectID.uuidString.lowercased())":{"files":{"main.rs":"a\\nb\\n"},"recordedAt":0}}
        """
        defaults.set(Data(legacy.utf8), forKey: "crabrix.contribution.v2")

        let ledger = CodeContributionLedger(defaults: defaults)
        let contribution = ledger.record(projectID: projectID, files: ["main.rs": "a\nb\n"])
        XCTAssertFalse(contribution.isFirstRun, "the old baseline still applies")
        XCTAssertEqual(contribution.changedLines, 0)
        XCTAssertNil(defaults.data(forKey: "crabrix.contribution.v2"), "converted, not left behind")
    }

    func testProjectsAreMeasuredIndependently() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        _ = ledger.record(projectID: UUID(), files: ["main.rs": "a\n"])
        let other = ledger.record(projectID: UUID(), files: ["main.rs": "a\n"])
        XCTAssertTrue(other.isFirstRun, "a different project starts from scratch")
    }

    func testSameNamedProjectsCannotShareABaseline() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let firstID = UUID()
        let secondID = UUID()

        _ = ledger.record(projectID: firstID, files: ["main.rs": "same name, first project"])
        let second = ledger.record(
            projectID: secondID,
            files: ["main.rs": "same name, second project"]
        )

        XCTAssertTrue(second.isFirstRun)
    }
}
