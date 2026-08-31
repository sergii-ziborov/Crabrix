import XCTest
@testable import Crabrix

final class AchievementTierTests: XCTestCase {
    func testEveryFamilyHasAscendingThresholds() {
        for family in CrabrixAchievementCatalog.families {
            XCTAssertFalse(family.thresholds.isEmpty, family.id)
            XCTAssertLessThanOrEqual(
                family.thresholds.count, AchievementTier.allCases.count,
                "\(family.id) has more rungs than there are tiers"
            )
            XCTAssertEqual(
                family.thresholds, family.thresholds.sorted(),
                "\(family.id) thresholds must ascend"
            )
            XCTAssertEqual(
                Set(family.thresholds).count, family.thresholds.count,
                "\(family.id) repeats a threshold, so two tiers unlock together"
            )
        }
    }

    func testTierIdentifiersAreUniqueAndStable() {
        let ids = CrabrixAchievementCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        // The persisted set is keyed on these, so the shape is part of the API.
        XCTAssertTrue(ids.contains("recall-runs.0"))
        XCTAssertTrue(ids.contains("recall-runs.4"))
    }

    func testATierIsOnlyEarnedOnceItsThresholdIsMet() {
        var state = CrabrixProgressState()
        let family = try! XCTUnwrap(CrabrixAchievementCatalog.family(id: "recall-runs"))

        state.codeRecallRuns = 1
        XCTAssertEqual(family.earnedTier(in: state), .bronze)
        state.codeRecallRuns = 10
        XCTAssertEqual(family.earnedTier(in: state), .silver)
        state.codeRecallRuns = 999
        XCTAssertEqual(family.earnedTier(in: state), .platinum)
        state.codeRecallRuns = 10_000
        XCTAssertEqual(family.earnedTier(in: state), .diamond)
    }

    func testOneRunNoLongerFinishesTheFamily() {
        // The whole point of the change: trying it once is Bronze, not done.
        var state = CrabrixProgressState()
        state.codeRecallRuns = 1
        let family = try! XCTUnwrap(CrabrixAchievementCatalog.family(id: "recall-runs"))
        XCTAssertNotNil(family.nextTarget(in: state))
        XCTAssertEqual(family.nextTarget(in: state)?.tier, .silver)
    }

    func testProgressIsClampedToTheTarget() {
        var state = CrabrixProgressState()
        state.codeRecallRuns = 50_000
        let bronze = try! XCTUnwrap(CrabrixAchievementCatalog.achievement(id: "recall-runs.0"))
        XCTAssertEqual(bronze.progress(state).current, bronze.target)
    }

    func testTheRatingLadderMatchesTheTopOfTheRankLadder() {
        let family = try! XCTUnwrap(CrabrixAchievementCatalog.family(id: "rating"))
        // A badge that disagreed with the rank shown next to it would be a bug
        // the reader could see. There are more ranks than tiers, so the badge
        // covers the top five rungs.
        XCTAssertEqual(family.thresholds, CrabrixRank.ladder.suffix(5).map(\.threshold))
    }

    func testCourseworkMeasuresTheRustPathAlone() {
        let family = try! XCTUnwrap(CrabrixAchievementCatalog.family(id: "lessons"))
        var state = CrabrixProgressState()
        // Enough Atlas steps to finish the whole ladder, if it counted them.
        state.lessonsCompleted = 600
        state.algorithmStudySteps = 400
        XCTAssertNil(
            family.earnedTier(in: state),
            "a language badge must not be earned without a language lesson"
        )

        state.rustLessonsCompleted = RustCourseCatalog.academyLessonCount
        XCTAssertEqual(family.earnedTier(in: state), .diamond)
        XCTAssertEqual(
            family.thresholds.last, RustCourseCatalog.academyLessonCount,
            "the last rung is the path itself"
        )
    }

    func testAtlasStudyHasItsOwnLadder() {
        let family = try! XCTUnwrap(CrabrixAchievementCatalog.family(id: "algorithm-study"))
        XCTAssertEqual(family.thresholds.last, AlgorithmCourseCatalog.studyStepCount)
        var state = CrabrixProgressState()
        state.algorithmStudySteps = AlgorithmCourseCatalog.studyStepCount
        XCTAssertEqual(family.earnedTier(in: state), .diamond)
    }

    func testRecallDepthIsAchievable() {
        let family = try! XCTUnwrap(CrabrixAchievementCatalog.family(id: "recall-depth"))
        XCTAssertLessThanOrEqual(
            family.thresholds.last ?? 0, CodeRecallDeck.maximumLines,
            "the top rung must be reachable in a real run"
        )
    }

    func testEveryFamilyHasDistinctTitlesAndIcons() {
        let titles = CrabrixAchievementCatalog.families.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "two ladders with one name are confusing")
        for family in CrabrixAchievementCatalog.families {
            XCTAssertFalse(family.systemImage.isEmpty, family.id)
            for rung in family.achievements {
                XCTAssertFalse(rung.detail.isEmpty, rung.id)
            }
        }
    }
}

@MainActor
final class AchievementMigrationTests: XCTestCase {
    func testAnOlderStateAdoptsTheTieredCatalogueWithoutCelebrating() throws {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        // A state written before tiers existed, with real progress in it.
        let legacy = """
        {
          "version": 1, "totalPoints": 900, "lessonsCompleted": 30,
          "buildsSucceeded": 60, "diagnosticsRepaired": 12,
          "practiceRoundsPassed": 8, "termTrainRuns": 20,
          "termTrainPairsMatched": 300, "termTrainBestStreak": 11,
          "bestTimedPairsPerMinute": 12, "packagesCompiled": 6,
          "unlockedAchievementIDs": ["first-build", "ten-builds", "first-lesson"]
        }
        """
        defaults.set(Data(legacy.utf8), forKey: "crabrix.progress.state.v1")

        let store = CrabrixProgressStore(defaults: defaults)

        // Progress survived the catalogue change.
        XCTAssertEqual(store.state.totalPoints, 900)
        XCTAssertEqual(store.state.buildsSucceeded, 60)
        // The single old lesson counter is split without inventing progress:
        // no pattern was solved, so all thirty are attributed to the Rust path.
        XCTAssertEqual(store.state.lessonsCompleted, 30)
        XCTAssertEqual(store.state.rustLessonsCompleted, 30)
        XCTAssertEqual(store.state.algorithmStudySteps, 0)
        // Tiers already satisfied are recorded...
        XCTAssertTrue(store.state.unlockedAchievementIDs.contains("builds.2"))
        XCTAssertTrue(store.state.unlockedAchievementIDs.contains("lessons.2"))
        // ...silently. A parade of modals for old work would be noise.
        XCTAssertTrue(store.pendingCelebration.isEmpty)
        // Stale ids from the old catalogue are gone.
        XCTAssertFalse(store.state.unlockedAchievementIDs.contains("first-build"))
        // And a rung not yet reached stays locked.
        XCTAssertFalse(store.state.unlockedAchievementIDs.contains("builds.3"))
    }

    func testANewTierStillCelebratesAfterMigration() throws {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let store = CrabrixProgressStore(defaults: defaults)
        store.record(.buildSucceeded(CodeContribution(addedLines: 5)))
        XCTAssertEqual(store.pendingCelebration.map(\.id), ["builds.0"])
    }
}
