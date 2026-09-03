import Foundation

/// A second teaching layer shared by every lesson.
///
/// `RustLessonWriting` owns the lesson-specific explanation and example. This
/// model turns that material into an active learning loop: trace the example,
/// reject a tempting misconception, transfer the rule, and connect it to the
/// surrounding curriculum. Keeping it derived means a newly added lesson cannot
/// silently fall back to the old one-card/one-question experience.
struct RustLessonDepth: Equatable, Sendable {
    struct TraceStep: Equatable, Sendable {
        let title: String
        let detail: String
    }

    struct Connection: Equatable, Sendable {
        enum Direction: Equatable, Sendable {
            case previous
            case next
        }

        let direction: Direction
        let title: String
        let concept: String
    }

    let traceSteps: [TraceStep]
    let misconception: String
    let correction: String
    let transferChallenge: String
    let connections: [Connection]
}

enum RustLessonDepthCatalog {
    static func depth(for lesson: RustLesson) -> RustLessonDepth {
        let writing = RustLessonLibrary.writing(for: lesson.id)
        let course = RustCourseCatalog.course(containingLessonID: lesson.id)
        let method = learningMethod(for: course?.id)
        let wrongAnswer = writing?.answers.enumerated().first(where: {
            $0.offset != writing?.correctAnswer
        })?.element

        return RustLessonDepth(
            traceSteps: [
                RustLessonDepth.TraceStep(
                    title: method.inventoryTitle,
                    detail: method.inventoryDetail
                ),
                RustLessonDepth.TraceStep(
                    title: "Predict before checking",
                    detail: writing?.task
                        ?? "State what should compile, what should run, and what evidence would prove your prediction."
                ),
                RustLessonDepth.TraceStep(
                    title: "Compare with evidence",
                    detail: writing?.success
                        ?? "Compare your prediction with the compiler result and explain any difference before editing."
                ),
            ],
            misconception: wrongAnswer.map { "“\($0)”" }
                ?? "Treating the example as syntax to memorise instead of a contract to test.",
            // Deliberately the rule, not `feedback`: the feedback is already
            // shown next to the answer, and a card that repeats the line above
            // it teaches nothing.
            correction: writing?.rule
                ?? "Return to the rule, identify the first conflicting assumption, and verify one intentional change.",
            transferChallenge: method.transferChallenge(for: lesson),
            connections: connections(around: lesson, in: course)
        )
    }

    private static func connections(
        around lesson: RustLesson,
        in course: RustCourse?
    ) -> [RustLessonDepth.Connection] {
        guard let course else { return [] }
        let lessons = course.units.flatMap(\.lessons)
        guard let index = lessons.firstIndex(where: { $0.id == lesson.id }) else { return [] }

        var result: [RustLessonDepth.Connection] = []
        if index > lessons.startIndex {
            let previous = lessons[lessons.index(before: index)]
            result.append(
                RustLessonDepth.Connection(
                    direction: .previous,
                    title: previous.title,
                    concept: previous.concept
                )
            )
        }
        let nextIndex = lessons.index(after: index)
        if nextIndex < lessons.endIndex {
            let next = lessons[nextIndex]
            result.append(
                RustLessonDepth.Connection(
                    direction: .next,
                    title: next.title,
                    concept: next.concept
                )
            )
        }
        return result
    }

    private static func learningMethod(for courseID: String?) -> LearningMethod {
        switch courseID {
        case "algorithms":
            LearningMethod(
                inventoryTitle: "Name the invariant",
                inventoryDetail: "Write down the state carried between steps, what remains true after every update, and the condition that guarantees termination.",
                transfer: "Change the visible input to an empty, duplicate-heavy, boundary, or adversarial case. Preserve the invariant and defend the promised complexity before running it."
            )
        case "ownership":
            LearningMethod(
                inventoryTitle: "Map ownership first",
                inventoryDetail: "For every binding, mark its owner, whether access is shared or mutable, and the line where that access ends.",
                transfer: "Change exactly one boundary in the sample — value, &T, or &mut T. Before compiling, list which bindings remain usable after each call."
            )
        case "projects":
            LearningMethod(
                inventoryTitle: "Map the project boundary",
                inventoryDetail: "Separate source modules, public API, manifest data, dependency graph, and build evidence before changing any one of them.",
                transfer: "Move one responsibility across a module or package boundary without changing behaviour. Predict which imports, tests, or lock data must change."
            )
        case "concurrency":
            LearningMethod(
                inventoryTitle: "Draw the event timeline",
                inventoryDetail: "Name each task or thread, the state it can reach, and every point where work can wait, race, block, or be cancelled.",
                transfer: "Add a second worker or cancellation point. Draw two possible event orders and state the invariant that both orders must preserve."
            )
        case "systems":
            LearningMethod(
                inventoryTitle: "State the invariant",
                inventoryDetail: "Write down what callers may assume, what the compiler cannot prove, and which boundary is responsible for preserving soundness or cost.",
                transfer: "Create the smallest counterexample that violates the sample's invariant, then repair the abstraction boundary instead of hiding the symptom."
            )
        case "interview":
            LearningMethod(
                inventoryTitle: "Frame the answer",
                inventoryDetail: "Start with the model, name the relevant constraint, then choose one concrete example and one failure mode that test the claim.",
                transfer: "Give a 60-second answer using model → tradeoff → edge case → evidence, then answer a follow-up that changes one constraint."
            )
        default:
            LearningMethod(
                inventoryTitle: "Inventory the values",
                inventoryDetail: "Name each value's type and starting value, then mark the expression that produces the lesson's result.",
                transfer: "Change one value, type, or boundary in the sample. Write the exact stdout or diagnostic you expect before asking rustc."
            )
        }
    }
}

private struct LearningMethod: Sendable {
    let inventoryTitle: String
    let inventoryDetail: String
    let transfer: String

    func transferChallenge(for lesson: RustLesson) -> String {
        "\(transfer) Keep the focus on \(lesson.concept.lowercased())."
    }
}
