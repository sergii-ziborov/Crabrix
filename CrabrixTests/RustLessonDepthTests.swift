import Testing
@testable import Crabrix

struct RustLessonDepthTests {
    @Test func everyLessonHasACompleteDeepLearningLoop() {
        let lessons = RustCourseCatalog.courses
            .flatMap(\.units)
            .flatMap(\.lessons)

        #expect(lessons.count == 742)
        for lesson in lessons {
            let depth = RustLessonDepthCatalog.depth(for: lesson)
            #expect(depth.traceSteps.count == 3, "\(lesson.id) needs three trace steps")
            #expect(depth.traceSteps.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
            #expect(!depth.misconception.isEmpty)
            #expect(!depth.correction.isEmpty)
            #expect(!depth.transferChallenge.isEmpty)
        }
    }

    @Test func misconceptionNeverUsesTheCorrectAnswer() {
        let lessons = RustCourseCatalog.courses
            .flatMap(\.units)
            .flatMap(\.lessons)

        for lesson in lessons {
            guard let writing = RustLessonLibrary.writing(for: lesson.id) else {
                Issue.record("Missing writing for \(lesson.id)")
                continue
            }
            let depth = RustLessonDepthCatalog.depth(for: lesson)
            let correct = "“\(writing.answers[writing.correctAnswer])”"
            #expect(depth.misconception != correct, "\(lesson.id) repeats the correct answer as a trap")
        }
    }

    @Test func courseSequenceCreatesUsefulConnections() {
        for course in RustCourseCatalog.courses {
            let lessons = course.units.flatMap(\.lessons)
            #expect(!lessons.isEmpty)

            for (index, lesson) in lessons.enumerated() {
                let directions = RustLessonDepthCatalog.depth(for: lesson).connections.map(\.direction)
                #expect(directions.contains(.previous) == (index > 0))
                #expect(directions.contains(.next) == (index < lessons.count - 1))
            }
        }
    }
}
