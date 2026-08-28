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

    /// The lesson immediately following `lessonID` in catalog order.
    ///
    /// A completed lesson is deliberately not skipped. `Continue learning` is
    /// also used while reviewing a finished course, where skipping completed
    /// entries would jump over the lesson the reader explicitly expects next.
    /// Finishing a course still continues into the next course.
    static func nextStep(
        after lessonID: String?,
        completedLessonIDs: Set<String>
    ) -> Step? {
        let order = catalogOrder()
        guard !order.isEmpty else { return nil }

        if let lessonID, let index = order.firstIndex(where: { $0.lessonID == lessonID }) {
            let followingIndex = order.index(after: index)
            if followingIndex < order.endIndex {
                return order[followingIndex]
            }
            // At the end of the catalog, repair an earlier gap if one exists.
            if let gap = order.first(where: { !completedLessonIDs.contains($0.lessonID) }) {
                return gap
            }
            return order[index]
        }

        return order.first { !completedLessonIDs.contains($0.lessonID) } ?? order.first
    }
}
