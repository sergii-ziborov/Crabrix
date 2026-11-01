import Foundation

enum RustLessonProgression {
    enum UnlockScope: Sendable {
        /// One continuous course: only the first unfinished lesson is ready.
        case course
        /// Every unit is its own learning path: the first unfinished lesson in
        /// each unit is ready, and completing one unit never gates another.
        case independentUnits
    }

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

    static func readyLessonIDs(
        in units: [RustLearningUnit],
        completedLessonIDs: Set<String>,
        scope: UnlockScope
    ) -> Set<String> {
        switch scope {
        case .course:
            return Set(
                nextLessonID(in: units, completedLessonIDs: completedLessonIDs)
                    .map { [$0] } ?? []
            )
        case .independentUnits:
            return Set(
                units.compactMap { unit in
                    unit.lessons.first { !completedLessonIDs.contains($0.id) }?.id
                }
            )
        }
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
    private static func catalogOrder(courses: [RustCourse]) -> [Step] {
        courses.flatMap { course in
            course.units.flatMap(\.lessons).map { Step(courseID: course.id, lessonID: $0.id) }
        }
    }

    /// False for a lesson its course map shows as locked: unfinished, and not the
    /// course's first unfinished lesson. Courses do not lock one another.
    static func isOpen(_ step: Step, completedLessonIDs: Set<String>, courses: [RustCourse]) -> Bool {
        guard !completedLessonIDs.contains(step.lessonID),
              let course = courses.first(where: { $0.id == step.courseID }) else { return true }
        return nextLessonID(in: course.units, completedLessonIDs: completedLessonIDs) == step.lessonID
    }

    /// The lesson immediately following `lessonID` in catalog order.
    ///
    /// A completed lesson is deliberately not skipped. `Continue learning` is
    /// also used while reviewing a finished course, where skipping completed
    /// entries would jump over the lesson the reader explicitly expects next.
    /// Finishing a course still continues into the next course.
    static func nextStep(
        after lessonID: String?,
        completedLessonIDs: Set<String>,
        courses: [RustCourse]
    ) -> Step? {
        let order = catalogOrder(courses: courses)
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

/// The order a quiz shows its answers in. Packs author the correct answer in
/// predictable positions, so without this a learner can pass by position alone.
///
/// This is display only: the stored answer, the hint, the trap card and every
/// validator keep using the original index. The order comes from the lesson's
/// ID and nothing else, so it survives reopening a lesson, relaunching and
/// updating the app. Swift's `hashValue` and `shuffled()` give none of that.
enum LessonAnswerOrder {
    /// Maps each display position to the original answer index.
    static func displayOrder(lessonID: String, count: Int) -> [Int] {
        var order = Array(0..<max(count, 0))
        guard order.count > 1 else { return order }
        // FNV-1a seeds SplitMix64, both fully specified here so that no library
        // or OS update can reorder a lesson the learner has already seen.
        var state = lessonID.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        func next() -> UInt64 {
            state &+= 0x9e37_79b9_7f4a_7c15
            var value = state
            value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
            value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
            return value ^ (value >> 31)
        }
        for position in stride(from: order.count - 1, to: 0, by: -1) {
            order.swapAt(position, Int(next() % UInt64(position + 1)))
        }
        return order
    }
}

/// What a reopened quick check shows. A completed lesson is always answered,
/// even if a pack has since moved the correct answer away from the saved index.
/// Otherwise its answer buttons stay disabled, Continue never enables, and the
/// summary page cannot be reached without resetting the course.
enum LessonAnswerRestoration {
    static func state(savedAnswer: Int?, isCompleted: Bool, correctAnswer: Int)
        -> (selected: Int?, lastWrong: Int?) {
        if isCompleted || savedAnswer == correctAnswer { return (correctAnswer, nil) }
        return (nil, savedAnswer)
    }
}
