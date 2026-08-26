import XCTest
@testable import Crabrix

final class RustLessonProgressionTests: XCTestCase {
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
