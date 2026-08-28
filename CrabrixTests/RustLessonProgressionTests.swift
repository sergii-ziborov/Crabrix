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
        // Derived rather than hardcoded, so growing the curriculum does not
        // break a test that is really about the counting logic.
        XCTAssertEqual(
            RustLessonProgression.completedCount(
                in: basics.units,
                completedLessonIDs: completed
            ),
            completed.count
        )
        XCTAssertGreaterThan(completed.count, 0)
    }
}

final class RustCurriculumCoverageTests: XCTestCase {
    private var allLessons: [RustLesson] {
        RustCourseCatalog.courses.flatMap { $0.units.flatMap(\.lessons) }
    }

    func testLessonIdentifiersAreUnique() {
        let ids = allLessons.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate lesson ids break navigation and progress")
    }

    func testEveryUnitIsReachableFromACourse() {
        let used = Set(RustCourseCatalog.courses.flatMap { $0.units.map(\.id) })
        let defined = Set(RustLearningPath.units.map(\.id))
        XCTAssertTrue(
            defined.subtracting(used).isEmpty,
            "unreachable units: \(defined.subtracting(used).sorted())"
        )
    }

    func testCurriculumCoversTheCoreOfTheLanguage() {
        let ids = Set(allLessons.map(\.id))
        // The topics a Rust course cannot claim completeness without.
        let required = [
            "ownership", "borrowing", "lifetimes", "slices", "copy-clone", "drop-order",
            "structs", "enums", "option-result", "collections", "strings", "pattern-matching",
            "generics", "traits", "closures", "iterators", "associated-types",
            "modules", "testing", "errors", "dependencies", "workspaces",
            "box", "rc-refcell", "deref-drop", "cycles",
            "concurrency", "channels", "shared-state", "send-sync",
            "futures", "async-runtime", "declarative-macros", "proc-macros",
            "unsafe", "ffi", "performance",
        ]
        let missing = required.filter { !ids.contains($0) }
        XCTAssertTrue(missing.isEmpty, "curriculum is missing: \(missing)")
    }

    func testEveryLessonHasNonEmptyMetadata() {
        for lesson in allLessons {
            XCTAssertFalse(lesson.title.trimmingCharacters(in: .whitespaces).isEmpty, lesson.id)
            XCTAssertFalse(lesson.concept.trimmingCharacters(in: .whitespaces).isEmpty, lesson.id)
            XCTAssertGreaterThan(lesson.minutes, 0, lesson.id)
        }
    }

    func testWrittenLessonContentIsComplete() {
        for lesson in allLessons {
            guard let writing = RustLessonLibrary.writing(for: lesson.id) else { continue }
            XCTAssertFalse(writing.summary.isEmpty, lesson.id)
            XCTAssertFalse(writing.explanation.isEmpty, lesson.id)
            XCTAssertFalse(writing.exampleCode.isEmpty, lesson.id)
            XCTAssertEqual(writing.answers.count, 3, "\(lesson.id) should offer three answers")
            XCTAssertTrue(
                writing.answers.indices.contains(writing.correctAnswer),
                "\(lesson.id) has an out-of-range correct answer"
            )
            // Snippets are read on a phone, so lines have to fit.
            for line in writing.exampleCode.split(separator: "\n", omittingEmptySubsequences: false) {
                XCTAssertLessThanOrEqual(
                    line.count, 52,
                    "\(lesson.id) example line is too wide for a phone: \(line)"
                )
            }
        }
    }
}
