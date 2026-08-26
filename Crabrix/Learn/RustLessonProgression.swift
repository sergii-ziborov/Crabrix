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
}
