import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// AI Learning State v1 (docs/ai-learning/PLAN.md, "Phase 5"; schema
/// crabrix-courses `academy/learning-state.schema.json`): a portable file the
/// learner owns. It is never the official record.
///
/// The app is a read-only producer. The encoder receives lesson IDs that the
/// caller already holds in memory, writes nothing, and has no field for
/// answers, flashcards, mastery, rating, code, room links, credentials or file
/// paths, so none can end up in the file.
enum AILearningState {
    static let format = "crabrix.ai-learning-state"
    static let schemaVersion = 1
    static let fileName = "crabrix-learning-state.json"
    static let teachingMode = "guided"
    static let source = "crabrix-ios"
    /// Readers reject more than this many `completed` or `credited` entries.
    static let maximumEntries = 10_000

    /// Who made the file: `crabrix-ios 1.2.0 (140)`.
    struct Producer: Equatable, Sendable {
        let version: String
        let build: String

        var appVersion: String { "\(version) (\(build))" }
        var label: String { "crabrix-ios \(appVersion)" }

        static var current: Producer {
            Producer(
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
            )
        }
    }

    /// The two progress stores the export may copy, as the app already holds
    /// them: `crabrix.learn.completedLessonIDs` and
    /// `crabrix.learn.creditedLessonIDs.v1` (`[target: bridge lesson]`).
    struct Progress: Equatable, Sendable {
        let completed: Set<String>
        let credited: [String: String]
        /// Lesson ID → installed course ID. A lesson whose course is no longer
        /// installed is exported with a null `courseId`.
        let courseIDs: [String: String]

        init(completed: Set<String>, credited: [String: String], courseIDs: [String: String]) {
            self.completed = completed
            self.credited = credited
            self.courseIDs = courseIDs
        }

        init(completed: Set<String>, credited: [String: String], courses: [RustCourse]) {
            var map: [String: String] = [:]
            for course in courses {
                for lesson in course.units.lazy.flatMap(\.lessons) where map[lesson.id] == nil {
                    map[lesson.id] = course.id
                }
            }
            self.init(completed: completed, credited: credited, courseIDs: map)
        }
    }

    struct CompletedLesson: Equatable, Sendable, Encodable {
        let courseId: String?
        let lessonId: String

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(courseId, forKey: .courseId)
            try container.encode(lessonId, forKey: .lessonId)
        }

        private enum CodingKeys: String, CodingKey { case courseId, lessonId }
    }

    struct CreditedLesson: Equatable, Sendable, Encodable {
        let courseId: String?
        let lessonId: String
        let viaLessonId: String

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(courseId, forKey: .courseId)
            try container.encode(lessonId, forKey: .lessonId)
            try container.encode(viaLessonId, forKey: .viaLessonId)
        }

        private enum CodingKeys: String, CodingKey { case courseId, lessonId, viaLessonId }
    }

    struct OfficialProgress: Equatable, Sendable, Encodable {
        let source: String
        let capturedAt: String
        let appVersion: String
        let completed: [CompletedLesson]
        let credited: [CreditedLesson]
    }

    struct Document: Equatable, Sendable, Encodable {
        let updatedAt: String
        let producer: String
        let currentLesson: AILearningLessonRef?
        let officialProgress: OfficialProgress?

        private enum CodingKeys: String, CodingKey {
            case format, schemaVersion, updatedAt, producer, learningPath, teachingMode,
                 currentLesson, learner, aiSession, officialProgress, evidence
        }

        /// Explicit nulls: a reader sees that the app has no path and no
        /// progress copy, rather than an absent key.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(AILearningState.format, forKey: .format)
            try container.encode(AILearningState.schemaVersion, forKey: .schemaVersion)
            try container.encode(updatedAt, forKey: .updatedAt)
            try container.encode(producer, forKey: .producer)
            try container.encodeNil(forKey: .learningPath)
            try container.encode(AILearningState.teachingMode, forKey: .teachingMode)
            try container.encode(currentLesson, forKey: .currentLesson)
            try container.encode(EmptyObject(), forKey: .learner)
            try container.encode(EmptyObject(), forKey: .aiSession)
            try container.encode(officialProgress, forKey: .officialProgress)
            try container.encode([EmptyObject](), forKey: .evidence)
        }
    }

    /// Learner and AI-session context are authored by the learner and their
    /// agent, never by the app.
    private struct EmptyObject: Encodable, Equatable {
        func encode(to encoder: Encoder) throws {
            _ = encoder.container(keyedBy: NoKeys.self)
        }
        private enum NoKeys: CodingKey {}
    }

    static func document(
        now: Date,
        producer: Producer,
        currentLesson: AILearningLessonRef?,
        progress: Progress?
    ) -> Document {
        let timestamp = rfc3339(now)
        return Document(
            updatedAt: timestamp,
            producer: String(producer.label.prefix(80)),
            currentLesson: currentLesson.flatMap { lesson in
                isIdentifier(lesson.courseId) && isIdentifier(lesson.lessonId) ? lesson : nil
            },
            officialProgress: progress.map { official($0, capturedAt: timestamp, producer: producer) }
        )
    }

    /// Sorted, deterministic JSON with sorted keys.
    static func encode(
        now: Date,
        producer: Producer,
        currentLesson: AILearningLessonRef?,
        progress: Progress?
    ) throws -> Data {
        try encode(document(now: now, producer: producer, currentLesson: currentLesson, progress: progress))
    }

    static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Foundation prints an empty array or object over three lines. Raw
        // newlines occur only between tokens (strings escape theirs), so
        // folding them back is purely cosmetic.
        let text = String(decoding: try encoder.encode(document), as: UTF8.self)
            .replacingOccurrences(of: #"\[\n\n *\]"#, with: "[]", options: .regularExpression)
            .replacingOccurrences(of: #"\{\n\n *\}"#, with: "{}", options: .regularExpression)
        return Data(text.utf8)
    }

    private static func official(_ progress: Progress, capturedAt: String, producer: Producer) -> OfficialProgress {
        func course(_ lessonID: String) -> String? {
            progress.courseIDs[lessonID].flatMap { isIdentifier($0) ? $0 : nil }
        }
        let completedIDs = progress.completed.filter(isIdentifier).sorted()
        let completed = completedIDs.prefix(maximumEntries).map {
            CompletedLesson(courseId: course($0), lessonId: $0)
        }
        // A lesson the learner finished themselves is a completion, not a credit.
        let credited = progress.credited
            .filter { !progress.completed.contains($0.key) && isIdentifier($0.key) && isIdentifier($0.value) }
            .sorted { $0.key < $1.key }
            .prefix(maximumEntries)
            .map { CreditedLesson(courseId: course($0.key), lessonId: $0.key, viaLessonId: $0.value) }
        return OfficialProgress(
            source: source,
            capturedAt: capturedAt,
            appVersion: String(producer.appVersion.prefix(40)),
            completed: Array(completed),
            credited: Array(credited)
        )
    }

    /// RFC 3339 UTC, whole seconds: `2026-11-23T18:00:00Z`.
    static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    /// The schema's id pattern, `^[a-z0-9][a-z0-9.-]{0,159}$`. A reader rejects
    /// a whole file with any other id, so such an id is left out instead.
    static func isIdentifier(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard let first = scalars.first, scalars.count <= 160 else { return false }
        func allowed(_ scalar: Unicode.Scalar, leading: Bool) -> Bool {
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
                || (!leading && (scalar == "." || scalar == "-"))
        }
        return allowed(first, leading: true) && scalars.dropFirst().allSatisfy { allowed($0, leading: false) }
    }
}

/// The export as a share-sheet item named `crabrix-learning-state.json`. The
/// JSON is built when a destination asks for it; nothing is written by the app.
struct AILearningStateFile: Transferable, Sendable {
    let currentLesson: AILearningLessonRef?
    let progress: AILearningState.Progress?
    let producer: AILearningState.Producer

    func data(now: Date = Date()) throws -> Data {
        try AILearningState.encode(now: now, producer: producer, currentLesson: currentLesson, progress: progress)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in try file.data() }
            .suggestedFileName(AILearningState.fileName)
    }
}
