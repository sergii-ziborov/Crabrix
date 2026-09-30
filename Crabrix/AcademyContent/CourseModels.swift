import Foundation

/// Versioned transport DTOs. No Swift enum representation is stored in CoursePacks.
struct CourseDTO: Decodable, Sendable {
    let id: String
    let language: String
    let contentVersion: String
    let order: Int
    let level: String
    let title: String
    let subtitle: String
    let systemImage: String
    let theme: String
    let unitIDs: [String]
}

struct CourseUnitDTO: Decodable, Sendable {
    let id: String
    let parentID: String
    let order: Int
    let level: Int
    let title: String
    let subtitle: String
    let lessonIDs: [String]
}

struct CourseLessonDTO: Decodable, Sendable {
    let id: String
    let parentID: String
    let order: Int
    let title: String
    let concept: String
    let minutes: Int
    let exerciseKind: String
    let writing: CourseWritingDTO
    let depth: CourseDepthDTO

    func runtimeLesson() throws -> RustLesson {
        let exercise: RustLesson.Exercise
        switch exerciseKind {
        case "runnable": exercise = .runnable
        case "borrowDiagnostic": exercise = .borrowDiagnostic
        case "multiFile": exercise = .multiFile
        case "algorithmChallenge": exercise = .algorithmChallenge
        case "planned": exercise = .planned
        default: throw CoursePackError.incompatibleCapability("exercise kind \(exerciseKind)")
        }
        return RustLesson(id: id, title: title, concept: concept, minutes: minutes, exercise: exercise)
    }
}

struct CourseWritingDTO: Decodable, Sendable {
    let summary: String
    let explanation: String
    let exampleCaption: String
    let exampleCode: String
    let task: String
    let success: String
    let rule: String
    let practiceCode: String
    let question: String
    let answers: [String]
    let correctAnswer: Int
    let feedback: String

    func runtimeWriting() throws -> RustLessonWriting {
        guard !answers.isEmpty, answers.indices.contains(correctAnswer) else {
            throw CoursePackError.manifestMismatch("question answers")
        }
        return RustLessonWriting(
            summary: summary, explanation: explanation, exampleCaption: exampleCaption,
            exampleCode: exampleCode, task: task, success: success, rule: rule,
            practiceCode: practiceCode, question: question, answers: answers,
            correctAnswer: correctAnswer, feedback: feedback
        )
    }
}

struct CourseDepthDTO: Decodable, Sendable {
    struct TraceStep: Decodable, Sendable { let title: String; let detail: String }
    struct Connection: Decodable, Sendable {
        let direction: String
        let title: String
        let concept: String
    }

    let traceSteps: [TraceStep]
    let misconception: String
    let correction: String
    let transferChallenge: String
    let connections: [Connection]

    func runtimeDepth() throws -> RustLessonDepth {
        let connections = try connections.map { source -> RustLessonDepth.Connection in
            let direction: RustLessonDepth.Connection.Direction
            switch source.direction {
            case "previous": direction = .previous
            case "next": direction = .next
            default: throw CoursePackError.incompatibleCapability("connection \(source.direction)")
            }
            return RustLessonDepth.Connection(
                direction: direction, title: source.title, concept: source.concept
            )
        }
        return RustLessonDepth(
            traceSteps: traceSteps.map { .init(title: $0.title, detail: $0.detail) },
            misconception: misconception, correction: correction,
            transferChallenge: transferChallenge, connections: connections
        )
    }
}

struct CourseOutputMatcherDTO: Decodable, Sendable {
    let kind: String
    let value: String

    func runtimeMatcher() throws -> LessonOutputMatcher {
        switch kind {
        case "exact": .exact(value)
        case "contains": .contains(value)
        case "differsFrom": .differsFrom(value)
        default: throw CoursePackError.incompatibleCapability("output matcher \(kind)")
        }
    }
}

struct CourseEvidenceDTO: Decodable, Sendable {
    let kind: String
    let expectedOutput: CourseOutputMatcherDTO?
    let requiresSourceChange: Bool?
    let requiredFiles: [String]?
    let removesDiagnostic: String?
    let requiredSourceFragments: [String]?
    let forbiddenSourceFragments: [String]?
    let correctAnswer: Int?

    func runtimeEvidence() throws -> LessonEvidence {
        switch kind {
        case "compilerRun":
            guard let expectedOutput, let requiresSourceChange, let requiredFiles else {
                throw CoursePackError.manifestMismatch("compilerRun evidence")
            }
            return .compilerRun(expectedOutput: try expectedOutput.runtimeMatcher(),
                                requiresSourceChange: requiresSourceChange, requiredFiles: requiredFiles)
        case "repair":
            guard let removesDiagnostic, let expectedOutput, let requiredSourceFragments else {
                throw CoursePackError.manifestMismatch("repair evidence")
            }
            return .repair(removesDiagnostic: removesDiagnostic,
                           expectedOutput: try expectedOutput.runtimeMatcher(),
                           requiredSourceFragments: requiredSourceFragments)
        case "algorithmChallenge":
            guard let expectedOutput, let requiredSourceFragments,
                  let forbiddenSourceFragments else {
                throw CoursePackError.manifestMismatch("algorithm evidence")
            }
            return .algorithmChallenge(
                expectedOutput: try expectedOutput.runtimeMatcher(),
                requiredSourceFragments: requiredSourceFragments,
                forbiddenSourceFragments: forbiddenSourceFragments
            )
        case "reasoning":
            guard let correctAnswer else { throw CoursePackError.manifestMismatch("reasoning evidence") }
            return .reasoning(correctAnswer: correctAnswer)
        default: throw CoursePackError.incompatibleCapability("evidence kind \(kind)")
        }
    }
}

struct CourseCheckDTO: Decodable, Sendable {
    let evidence: CourseEvidenceDTO
    /// The Atlas challenge is retained as a raw, data-only JSON object until
    /// its existing project/verification UI is migrated to this repository.
    let challenge: CourseChallengeDTO?
}

struct CourseChallengeDTO: Decodable, Sendable {
    struct VerificationCase: Decodable, Sendable {
        let kind: String
        let input: String
        let expectedAnswer: String
    }
    let lessonID: String
    let patternID: String
    let projectName: String
    let source: String
    let verificationSource: String
    let verificationCases: [VerificationCase]
    let expectedOutput: String
    let requiredSourceFragments: [String]
    let forbiddenSourceFragments: [String]
}

struct CourseProjectTemplate: Sendable {
    let name: String
    let entryFile: String
    let files: [String: String]
}

struct CourseTermPairDTO: Decodable, Sendable {
    let id: String
    let order: Int
    let topic: String
    let term: String
    let description: String
}
