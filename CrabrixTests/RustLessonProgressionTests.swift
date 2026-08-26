import XCTest
@testable import Crabrix

final class RustLessonProgressionTests: XCTestCase {
    func testCatalogFindsCourseAndLessonByStableIdentifiers() throws {
        let course = try XCTUnwrap(RustCourseCatalog.course(id: "basics"))
        let lesson = try XCTUnwrap(RustCourseCatalog.lesson(id: "variables"))

        XCTAssertEqual(course.title, "Rust Basics")
        XCTAssertEqual(lesson.title, "Variables")
        XCTAssertEqual(
            RustCourseCatalog.course(containingLessonID: lesson.id)?.id,
            course.id
        )
    }

    func testCatalogReturnsNilForUnknownIdentifiers() {
        XCTAssertNil(RustCourseCatalog.course(id: "missing-course"))
        XCTAssertNil(RustCourseCatalog.lesson(id: "missing-lesson"))
        XCTAssertNil(RustCourseCatalog.course(containingLessonID: "missing-lesson"))
    }

    func testSuccessfulFirstLessonUnlocksVariables() throws {
        let basics = try XCTUnwrap(RustCourseCatalog.courses.first { $0.id == "basics" })

        XCTAssertEqual(
            RustLessonProgression.nextLessonID(
                in: basics.units,
                completedLessonIDs: ["hello-rust"]
            ),
            "variables"
        )
        XCTAssertEqual(
            RustLessonProgression.completedCount(
                in: basics.units,
                completedLessonIDs: ["hello-rust"]
            ),
            1
        )
    }

    func testCourseCompletesWhenEveryLessonIDIsRecorded() throws {
        let basics = try XCTUnwrap(RustCourseCatalog.courses.first { $0.id == "basics" })
        let completed = Set(RustLessonProgression.lessons(in: basics.units).map(\.id))

        XCTAssertNil(
            RustLessonProgression.nextLessonID(
                in: basics.units,
                completedLessonIDs: completed
            )
        )
        XCTAssertEqual(
            RustLessonProgression.completedCount(
                in: basics.units,
                completedLessonIDs: completed
            ),
            8
        )
    }
}
