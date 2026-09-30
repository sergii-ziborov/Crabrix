import Foundation
import XCTest
@testable import Crabrix

final class CourseBootstrapTests: XCTestCase {
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
}
