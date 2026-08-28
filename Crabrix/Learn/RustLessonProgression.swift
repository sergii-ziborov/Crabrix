import Foundation

enum RustLessonProgression {
    static func lessons(in units: [RustLearningUnit]) -> [RustLesson] {
        units.flatMap(\.lessons)
    }

    static func nextLessonID(
        in units: [RustLearningUnit],
        completedLessonIDs: Set<String>
    ) -> String? {
        lessons(in: units)
            .first(where: { !completedLessonIDs.contains($0.id) })?
            .id
    }

    static func completedCount(
        in units: [RustLearningUnit],
        completedLessonIDs: Set<String>
    ) -> Int {
        lessons(in: units).filter { completedLessonIDs.contains($0.id) }.count
    }

    /// Where "Continue learning" should land.
    struct Step: Equatable, Sendable {
        let courseID: String
        let lessonID: String
    }

    /// Every lesson in catalog order, paired with the course it belongs to.
    private static func catalogOrder() -> [Step] {
        RustCourseCatalog.courses.flatMap { course in
            course.units.flatMap(\.lessons).map { Step(courseID: course.id, lessonID: $0.id) }
        }
    }

    /// The lesson that follows `lessonID`, skipping anything already finished.
    ///
    /// Finishing the last lesson of a course continues into the next course, so
    /// the learner is always handed a concrete next screen rather than the full
    /// course list.
    static func nextStep(
        after lessonID: String?,
        completedLessonIDs: Set<String>
    ) -> Step? {
        let order = catalogOrder()
        guard !order.isEmpty else { return nil }

        if let lessonID, let index = order.firstIndex(where: { $0.lessonID == lessonID }) {
            let following = order[order.index(after: index)...]
            if let unfinished = following.first(where: { !completedLessonIDs.contains($0.lessonID) }) {
                return unfinished
            }
            // Everything after it is done, so fall back to any earlier gap.
            if let gap = order.first(where: { !completedLessonIDs.contains($0.lessonID) }) {
                return gap
            }
            // The whole catalog is complete; stay on the lesson just finished.
            return following.first ?? order[index]
        }

        return order.first { !completedLessonIDs.contains($0.lessonID) } ?? order.first
    }
}
