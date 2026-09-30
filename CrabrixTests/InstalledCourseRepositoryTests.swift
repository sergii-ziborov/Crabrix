import Foundation
import XCTest
@testable import Crabrix

final class InstalledCourseRepositoryTests: XCTestCase {
    func testAllBundledPacksReadAsExistingAcademyModels() async throws {
        let bundle = Bundle.main
        let packs = try XCTUnwrap(bundle.url(forResource: "MigrationCoursePacks", withExtension: nil))
        let keyring = try JSONDecoder().decode(
            CourseKeyring.self,
            from: Data(contentsOf: packs.appending(path: "production-keyring.json"))
        )
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        for course in RustCourseCatalog.courses {
            let descriptor = try Data(contentsOf: packs.appending(path: "\(course.id).descriptor.json"))
            let archive = packs.appending(path: "\(course.id)-1.0.1.zip")
            _ = try await installer.install(descriptorBytes: descriptor,
                                            downloadedArchive: archive, keyring: keyring)
        }
        let records = try await installer.installed()
        let repository = try InstalledCourseRepository(root: root, records: records, keyring: keyring)
        XCTAssertEqual(repository.courses.map(\.id), RustCourseCatalog.courses.map(\.id))
        XCTAssertEqual(repository.courses.flatMap(\.units).flatMap(\.lessons).count, 742)
        XCTAssertEqual(repository.termPairs().count, 358)
        XCTAssertEqual(repository.loaded.values.reduce(0) { $0 + $1.challenges.count }, 200)
        XCTAssertEqual(repository.loaded.values.reduce(0) { $0 + $1.projects.count }, 204)
        for pattern in AlgorithmCourseCatalog.patterns {
            let lessonID = pattern.lessonID(.challenge)
            XCTAssertEqual(
                repository.challenge(for: lessonID),
                AlgorithmCourseCatalog.challenge(for: lessonID),
                "Atlas validator changed for \(pattern.id)"
            )
        }

        for (currentCourse, oldCourse) in zip(repository.courses, RustCourseCatalog.courses) {
            XCTAssertEqual(currentCourse.title, oldCourse.title)
            XCTAssertEqual(currentCourse.subtitle, oldCourse.subtitle)
            XCTAssertEqual(currentCourse.units.map(\.id), oldCourse.units.map(\.id))
            for (currentUnit, oldUnit) in zip(currentCourse.units, oldCourse.units) {
                XCTAssertEqual(currentUnit.lessons.map(\.id), oldUnit.lessons.map(\.id))
                for (currentLesson, oldLesson) in zip(currentUnit.lessons, oldUnit.lessons) {
                    XCTAssertEqual(currentLesson.title, oldLesson.title)
                    XCTAssertEqual(currentLesson.concept, oldLesson.concept)
                    XCTAssertEqual(currentLesson.minutes, oldLesson.minutes)
                    XCTAssertEqual(repository.evidence(for: currentLesson.id), oldLesson.evidence)
                    XCTAssertEqual(repository.depth(for: currentLesson.id),
                                   RustLessonDepthCatalog.depth(for: oldLesson))
                    let oldWriting = try XCTUnwrap(RustLessonLibrary.writing(for: oldLesson.id))
                    let newWriting = try XCTUnwrap(repository.writing(for: currentLesson.id))
                    XCTAssertEqual(newWriting.summary, oldWriting.summary)
                    XCTAssertEqual(newWriting.explanation, oldWriting.explanation)
                    XCTAssertEqual(newWriting.exampleCode, oldWriting.exampleCode)
                    XCTAssertEqual(newWriting.practiceCode, oldWriting.practiceCode)
                    XCTAssertEqual(newWriting.question, oldWriting.question)
                    XCTAssertEqual(newWriting.answers, oldWriting.answers)
                    XCTAssertEqual(newWriting.correctAnswer, oldWriting.correctAnswer)
                    XCTAssertEqual(newWriting.feedback, oldWriting.feedback)
                }
            }
        }
    }
}
