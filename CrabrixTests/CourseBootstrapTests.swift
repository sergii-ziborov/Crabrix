import Foundation
import XCTest
@testable import Crabrix

final class CourseBootstrapTests: XCTestCase {
    func testFirstLaunchDecisionPersistsBeforeNewProgressIsWritten() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        XCTAssertEqual(CourseLaunchPolicy.resolve(defaults: defaults, supportRoot: root), .newLearner)
        defaults.set(Data("new progress".utf8), forKey: "crabrix.progress.state.v1")
        XCTAssertEqual(CourseLaunchPolicy.resolve(defaults: defaults, supportRoot: root), .newLearner)
    }

    func testLegacyProgressOrProjectsSelectFullOfflineMigration() throws {
        let progressSuite = UUID().uuidString
        let progressDefaults = try XCTUnwrap(UserDefaults(suiteName: progressSuite))
        defer { progressDefaults.removePersistentDomain(forName: progressSuite) }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        progressDefaults.set(["basics-intro"], forKey: "crabrix.learn.completedLessonIDs")
        XCTAssertEqual(
            CourseLaunchPolicy.resolve(defaults: progressDefaults, supportRoot: root),
            .existingLearner
        )

        let projectSuite = UUID().uuidString
        let projectDefaults = try XCTUnwrap(UserDefaults(suiteName: projectSuite))
        defer { projectDefaults.removePersistentDomain(forName: projectSuite) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appending(path: "project-index.json"))
        XCTAssertEqual(
            CourseLaunchPolicy.resolve(defaults: projectDefaults, supportRoot: root),
            .existingLearner
        )

        let settingsSuite = UUID().uuidString
        let settingsDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuite))
        defer { settingsDefaults.removePersistentDomain(forName: settingsSuite) }
        settingsDefaults.set("dark", forKey: "crabrix.appearance")
        XCTAssertEqual(
            CourseLaunchPolicy.resolve(defaults: settingsDefaults,
                                       supportRoot: root.appending(path: "empty")),
            .existingLearner
        )
    }

    func testFreshInstallActivatesStarterAndOffersRemainingCatalog() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bootstrap = try CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        )
        let installed = try await bootstrap.activateBundledBaseline(for: .newLearner)
        XCTAssertEqual(installed.courses.map(\.id), ["basics"])
        let installedLessonIDs = Set(installed.courses.flatMap(\.units).flatMap(\.lessons).map(\.id))
        XCTAssertFalse(installed.practiceQuestions().isEmpty)
        XCTAssertTrue(installed.practiceQuestions().allSatisfy {
            installedLessonIDs.contains($0.topic)
        })
        XCTAssertTrue(installed.recallSnippets().allSatisfy {
            installedLessonIDs.contains($0.topic)
        })
        XCTAssertTrue(installed.trainableTermPairs().allSatisfy {
            installedLessonIDs.contains($0.topic)
        })
        XCTAssertEqual(try bootstrap.bundledCatalog().courses.count, 7)
        let afterRelaunch = try await bootstrap.activateBundledBaseline(for: .newLearner)
        XCTAssertEqual(afterRelaunch.courses.map(\.id), ["basics"])
    }

    func testBundledBaselineInstallsOfflineAndRelaunchKeepsIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            if FileManager.default.fileExists(atPath: root.path) {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let bootstrap = try CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        )
        let first = try await bootstrap.activateBundledBaseline()
        let second = try await bootstrap.activateBundledBaseline()
        XCTAssertEqual(first.courses.map(\.id), second.courses.map(\.id))
        XCTAssertEqual(first.courses.flatMap(\.units).flatMap(\.lessons).count, 742)
        XCTAssertEqual(
            first.loaded.mapValues(\.archiveSHA256), second.loaded.mapValues(\.archiveSHA256)
        )
    }

    func testInstalledPracticeDecksMatchCompleteLegacyBaseline() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try await CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        ).activateBundledBaseline()

        XCTAssertEqual(repository.practiceQuestions(), RustQuestionBank.all)
        XCTAssertEqual(repository.recallSnippets(), CodeRecallDeck.all)
        XCTAssertEqual(
            repository.trainableTermPairs().sorted { $0.id < $1.id },
            TermTrainDeck.all.sorted { $0.id < $1.id }
        )
    }

    func testInstalledAtlasMethodMetadataMatchesLegacyBaseline() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try await CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        ).activateBundledBaseline()
        let methods = repository.algorithmMethods()
        let legacy = AlgorithmCourseCatalog.categories

        XCTAssertEqual(methods.count, legacy.count)
        for (method, category) in zip(methods, legacy) {
            XCTAssertEqual(method.id, category.id)
            XCTAssertEqual(method.title, category.title)
            XCTAssertEqual(method.subtitle, category.subtitle)
            XCTAssertEqual(method.systemImage, category.systemImage)
            XCTAssertEqual(method.achievementTitle, category.achievementTitle)
            XCTAssertEqual(method.patternIDs, category.patterns.map(\.id))
        }
    }

    func testProfileTotalsReflectInstalledPacksAfterAtlasRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bootstrap = try CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        )
        let complete = try await bootstrap.activateBundledBaseline()
        XCTAssertEqual(complete.learningTotals(), CourseLearningTotals(
            installedLessons: 742, rustLessons: 142,
            atlasStudySteps: 400, atlasChallenges: 200
        ))

        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        try await installer.uninstall(courseID: "algorithms", language: "en")
        let remaining = try await bootstrap.loadInstalled()
        XCTAssertEqual(remaining.learningTotals(), CourseLearningTotals(
            installedLessons: 142, rustLessons: 142,
            atlasStudySteps: 0, atlasChallenges: 0
        ))
    }

    @MainActor
    func testAtlasAchievementsUseInstalledMethodMetadataWithoutReaward() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try await CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        ).activateBundledBaseline()
        let suite = "crabrix.atlas.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        store.configureAcademy(repository: repository)
        let methods = repository.algorithmMethods()

        XCTAssertEqual(store.atlasMethodCount, methods.count)
        XCTAssertEqual(store.atlasPatternCount, 200)
        for method in methods {
            let family = try XCTUnwrap(store.achievementFamilies.first {
                $0.id == "algorithm-\(method.id)"
            })
            XCTAssertEqual(family.title, method.achievementTitle)
            XCTAssertEqual(family.systemImage, method.systemImage)
        }

        let firstPattern = try XCTUnwrap(methods.first?.patternIDs.first)
        let challenge = try XCTUnwrap(repository.challenge(
            for: "algorithm.\(firstPattern).challenge"
        ))
        XCTAssertTrue(store.recordAlgorithmSolved(challenge: challenge))
        let earned = store.state.unlockedAchievementIDs
        store.clearCelebration()
        store.configureAcademy(repository: repository)
        XCTAssertEqual(store.state.unlockedAchievementIDs, earned)
        XCTAssertTrue(store.pendingCelebration.isEmpty)
        XCTAssertFalse(store.recordAlgorithmSolved(challenge: challenge))
    }

    func testDeletingLocalMaterialDoesNotReactivateItOnRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bootstrap = try CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        )
        let first = try await bootstrap.activateBundledBaseline()
        let lessonID = try XCTUnwrap(first.course(id: "basics")?.units.first?.lessons.first?.id)
        let openSession = try XCTUnwrap(CourseSession(lessonID: lessonID, repository: first))
        let lesson = try XCTUnwrap(first.lesson(id: lessonID))
        let execution = try XCTUnwrap(CourseLessonExecution(lesson: lesson, session: openSession))
        let pinnedHint = try XCTUnwrap(execution.hint)
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        try await installer.uninstall(courseID: "basics", language: "en")

        let afterRelaunch = try await bootstrap.activateBundledBaseline()
        XCTAssertNil(afterRelaunch.course(id: "basics"))
        XCTAssertNotNil(openSession.repository.lesson(id: lessonID))
        XCTAssertEqual(execution.hint, pinnedHint)
        XCTAssertEqual(execution.sessionToken, openSession.token)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appending(path: "basics/en/1.0.1/course.json").path
        ))
        XCTAssertEqual(afterRelaunch.courses.count, first.courses.count - 1)
    }

    func testAttemptEvidenceDecodesOldRecordsWithoutInventingCourseVersion() throws {
        let evidence = LessonAttemptEvidence(
            lessonID: "borrowing", projectRevision: "source-hash",
            validatorVersion: LessonAttemptEvidence.validatorVersion,
            compilerVersion: "legacy-rustc", result: .passed,
            diagnosticCodes: [], stdoutHash: nil, completedAt: Date(timeIntervalSince1970: 0)
        )
        let encoded = try JSONEncoder().encode(evidence)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "identity")
        let legacyBytes = try JSONSerialization.data(withJSONObject: legacyObject)
        let restored = try JSONDecoder().decode(LessonAttemptEvidence.self, from: legacyBytes)

        XCTAssertEqual(restored.lessonID, "borrowing")
        XCTAssertEqual(restored.projectRevision, "source-hash")
        XCTAssertNil(restored.identity)

        let identity = LessonAttemptIdentity(
            courseID: "ownership", language: "en", contentVersion: "1.0.1",
            lessonID: "borrowing", exerciseID: "borrowing",
            validatorVersion: LessonAttemptEvidence.validatorVersion,
            toolchainID: "artifacts-test-7", projectID: UUID(),
            projectRevision: "source-hash"
        )
        let modern = LessonAttemptEvidence(
            lessonID: evidence.lessonID, projectRevision: evidence.projectRevision,
            validatorVersion: evidence.validatorVersion,
            compilerVersion: evidence.compilerVersion, result: evidence.result,
            diagnosticCodes: evidence.diagnosticCodes, stdoutHash: evidence.stdoutHash,
            completedAt: evidence.completedAt, identity: identity
        )
        XCTAssertEqual(try JSONDecoder().decode(
            LessonAttemptEvidence.self, from: JSONEncoder().encode(modern)
        ), modern)
    }
}
