import CryptoKit
import Foundation

/// `crabrix.learning-link-snapshot` v1 (docs/ai-learning/learning-link.md,
/// "Snapshot plaintext"): what the learner's agent can read through their
/// learning link. Written only by the app, from the existing stores, read-only.
///
/// The input has no field for answers, code, projects, room links, XP or
/// account data, so none can reach the snapshot.
enum LearningLinkSnapshot {
    static let format = "crabrix.learning-link-snapshot"
    static let schemaVersion = 1
    static let maximumTopics = 30
    static let maximumRecentLessons = 10
    static let maximumCourses = 100
    /// More than every lesson the Academy has; a safety net for the size limit.
    static let maximumEntries = 5_000
    static let maximumEnvelopeBytes = 256 * 1_024

    struct Input: Sendable {
        /// `crabrix.learn.completedLessonIDs`.
        var completed: Set<String>
        /// `crabrix.learn.creditedLessonIDs.v1`: target → bridge lesson.
        var credited: [String: String]
        var catalog: LearningLinkCatalog
        /// `crabrix.mastery.v1`.
        var mastery: [String: TopicMasteryRecord]
        /// `crabrix.ai.recentLessons.v1`, newest first.
        var recentLessons: [AILearningLessonRef]
        var tutorPlan: TutorPlan
        var now: Date
        /// `1.2.0 (140)`.
        var app: String
        /// `iPhone` or `iPad`.
        var device: String
    }

    enum Failure: Error, Equatable { case tooLarge }

    // MARK: Document

    struct LessonRef: Encodable, Equatable {
        let courseId: String?
        let lessonId: String

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(courseId, forKey: .courseId)
            try container.encode(lessonId, forKey: .lessonId)
        }
        private enum CodingKeys: String, CodingKey { case courseId, lessonId }
    }

    struct Credit: Encodable, Equatable {
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

    struct Course: Encodable, Equatable {
        let courseId: String
        let title: String
        let version: String?
        let lessonCount: Int
        let completed: Int

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(courseId, forKey: .courseId)
            try container.encode(title, forKey: .title)
            try container.encode(version, forKey: .version)
            try container.encode(lessonCount, forKey: .lessonCount)
            try container.encode(completed, forKey: .completed)
        }
        private enum CodingKeys: String, CodingKey { case courseId, title, version, lessonCount, completed }
    }

    struct Topic: Encodable, Equatable {
        let lessonId: String
        let attempts: Int
        let correct: Int
        let dueAt: String
    }

    struct Assigned: Encodable, Equatable {
        let courseId: String
        let lessonId: String
        let assignedAt: String
        let done: Bool
        let reason: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(courseId, forKey: .courseId)
            try container.encode(lessonId, forKey: .lessonId)
            try container.encode(assignedAt, forKey: .assignedAt)
            try container.encode(done, forKey: .done)
            try container.encode(reason, forKey: .reason)
        }
        private enum CodingKeys: String, CodingKey { case courseId, lessonId, assignedAt, done, reason }
    }

    struct Tutor: Encodable, Equatable {
        let pathId: String?
        let goal: String?
        let concepts: [String]
        let note: String?
        let assigned: [Assigned]

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(pathId, forKey: .pathId)
            try container.encode(goal, forKey: .goal)
            try container.encode(concepts, forKey: .concepts)
            try container.encode(note, forKey: .note)
            try container.encode(assigned, forKey: .assigned)
        }
        private enum CodingKeys: String, CodingKey { case pathId, goal, concepts, note, assigned }
    }

    struct Document: Encodable, Equatable {
        let capturedAt: String
        let app: String
        let device: String
        let completed: [LessonRef]
        let credited: [Credit]
        let currentLesson: LessonRef?
        let recentLessons: [LessonRef]
        let courses: [Course]
        let topics: [Topic]
        let tutor: Tutor

        private enum CodingKeys: String, CodingKey {
            case format, schemaVersion, capturedAt, app, device, completed, credited,
                 currentLesson, recentLessons, courses, topics, tutor
        }

        func replacing(topics: [Topic], recentLessons: [LessonRef]) -> Document {
            Document(capturedAt: capturedAt, app: app, device: device, completed: completed, credited: credited,
                     currentLesson: recentLessons.first, recentLessons: recentLessons, courses: courses,
                     topics: topics, tutor: tutor)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(LearningLinkSnapshot.format, forKey: .format)
            try container.encode(LearningLinkSnapshot.schemaVersion, forKey: .schemaVersion)
            try container.encode(capturedAt, forKey: .capturedAt)
            try container.encode(app, forKey: .app)
            try container.encode(device, forKey: .device)
            try container.encode(completed, forKey: .completed)
            try container.encode(credited, forKey: .credited)
            try container.encode(currentLesson, forKey: .currentLesson)
            try container.encode(recentLessons, forKey: .recentLessons)
            try container.encode(courses, forKey: .courses)
            try container.encode(topics, forKey: .topics)
            try container.encode(tutor, forKey: .tutor)
        }
    }

    static func document(_ input: Input) -> Document {
        let isID = AILearningState.isIdentifier
        let catalog = input.catalog
        func course(_ lessonID: String) -> String? { catalog.lessonCourse[lessonID] }

        let completed = input.completed.filter(isID).sorted().prefix(maximumEntries)
            .map { LessonRef(courseId: course($0), lessonId: $0) }
        // A lesson the learner finished themselves is a completion, not a credit.
        let credited = input.credited
            .filter { !input.completed.contains($0.key) && isID($0.key) && isID($0.value) }
            .sorted { $0.key < $1.key }
            .prefix(maximumEntries)
            .map { Credit(courseId: course($0.key), lessonId: $0.key, viaLessonId: $0.value) }

        var seenRecent = Set<String>()
        let recent = input.recentLessons
            .filter { isID($0.courseId) && isID($0.lessonId) && seenRecent.insert($0.lessonId).inserted }
            .prefix(maximumRecentLessons)
            .map { LessonRef(courseId: $0.courseId, lessonId: $0.lessonId) }

        let courses = catalog.courses
            .filter { isID($0.id) }
            .sorted { $0.id < $1.id }
            .prefix(maximumCourses)
            .map { entry in
                Course(courseId: entry.id, title: clean(entry.title, limit: 120) ?? entry.id,
                       version: entry.version.flatMap(versionText),
                       lessonCount: entry.lessonIDs.count,
                       completed: entry.lessonIDs.filter(input.completed.contains).count)
            }

        let topics = input.mastery.values
            .filter { $0.attempts > 0 && isID($0.topic) }
            .sorted { lhs, rhs in
                let left = Double(lhs.correct) / Double(lhs.attempts)
                let right = Double(rhs.correct) / Double(rhs.attempts)
                if left != right { return left < right }
                if lhs.attempts != rhs.attempts { return lhs.attempts > rhs.attempts }
                return lhs.topic < rhs.topic
            }
            .prefix(maximumTopics)
            .map { Topic(lessonId: $0.topic, attempts: $0.attempts, correct: $0.correct,
                         dueAt: AILearningState.rfc3339($0.dueAt)) }

        // The tutor's own plan, re-checked so one bad stored value can never
        // make the MCP server refuse the whole snapshot.
        let plan = input.tutorPlan
        let focusNote = plan.focus.flatMap { focus in focus.note.map { (text: $0, at: focus.updatedAt) } }
        let assignNote = plan.note.map { (text: $0.text, at: $0.createdAt) }
        let latestNote = [focusNote, assignNote].compactMap { $0 }.max { $0.at < $1.at }?.text
        let tutor = Tutor(
            pathId: plan.focus?.pathId.flatMap { TutorMessageValidator.isPathID($0) ? $0 : nil },
            goal: plan.focus?.goal.flatMap { TutorMessageValidator.plainText($0, limit: TutorMessageValidator.goalLimit) },
            concepts: Array((plan.focus?.concepts ?? [])
                .compactMap { TutorMessageValidator.plainText($0, limit: TutorMessageValidator.conceptLimit) }
                .prefix(TutorMessageValidator.maximumConcepts)),
            note: latestNote.flatMap { TutorMessageValidator.plainText($0, limit: TutorMessageValidator.noteLimit) },
            assigned: plan.assignments
                .filter { isID($0.courseId) && isID($0.lessonId) }
                .prefix(TutorPlan.maximumAssignments)
                .map {
                    Assigned(courseId: $0.courseId, lessonId: $0.lessonId,
                             assignedAt: AILearningState.rfc3339($0.assignedAt),
                             done: input.completed.contains($0.lessonId),
                             reason: $0.reason.flatMap { TutorMessageValidator.plainText($0, limit: TutorMessageValidator.reasonLimit) })
                }
        )

        return Document(
            capturedAt: AILearningState.rfc3339(input.now),
            app: clean(input.app, limit: 40) ?? "0",
            device: input.device == "iPad" ? "iPad" : "iPhone",
            completed: Array(completed),
            credited: Array(credited),
            currentLesson: recent.first,
            recentLessons: Array(recent),
            courses: courses,
            topics: Array(topics),
            tutor: tutor
        )
    }

    /// Compact JSON with sorted keys: the same input gives the same bytes.
    static func encode(_ input: Input) throws -> Data {
        try encode(document(input))
    }

    static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    /// The same document, indented, for "See exactly what is sent".
    static func preview(_ input: Input) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(document(input))).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Identifies the content regardless of when it was captured, so an
    /// unchanged snapshot is not uploaded again.
    static func contentDigest(_ input: Input) throws -> String {
        var fixed = input
        fixed.now = Date(timeIntervalSince1970: 0)
        return SHA256.hash(data: try encode(fixed)).map { String(format: "%02x", $0) }.joined()
    }

    /// The encrypted upload, refused above the website's 256 KB.
    static func envelope(_ plaintext: Data, keys: LearningLinkCrypto.Keys, linkID: String) throws -> Data {
        guard plaintext.count <= maximumPlaintextBytes else { throw Failure.tooLarge }
        let envelope = try LearningLinkCrypto.seal(plaintext, key: keys.encryption, linkID: linkID, purpose: .snapshot)
        let data = try envelope.encoded()
        guard data.count <= maximumEnvelopeBytes else { throw Failure.tooLarge }
        return data
    }

    /// 256 KB of envelope leaves 196,560 bytes of plaintext (the website's
    /// implementation notes): the envelope adds 42 bytes and base64url a third.
    static let maximumPlaintextBytes = 196_560

    /// The plaintext that fits: the full snapshot, else without topics, else
    /// also without recent lessons. Progress itself is never trimmed.
    static func fittingPlaintext(_ input: Input) throws -> Data {
        var trimmed = document(input)
        var data = try encode(trimmed)
        if data.count > maximumPlaintextBytes {
            trimmed = trimmed.replacing(topics: [], recentLessons: trimmed.recentLessons)
            data = try encode(trimmed)
        }
        if data.count > maximumPlaintextBytes {
            trimmed = trimmed.replacing(topics: [], recentLessons: [])
            data = try encode(trimmed)
        }
        guard data.count <= maximumPlaintextBytes else { throw Failure.tooLarge }
        return data
    }

    /// Plain text cut to `limit` code points, as the SDK counts them.
    private static func clean(_ text: String, limit: Int) -> String? {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.prefix(limit * 2))
        guard let cleaned = TutorMessageValidator.plainText(String(scalars), limit: limit * 2) else { return nil }
        var cut = String.UnicodeScalarView()
        cut.append(contentsOf: cleaned.unicodeScalars.prefix(limit))
        return String(cut).trimmingCharacters(in: .whitespaces)
    }

    private static func versionText(_ version: String) -> String? {
        let allowed = version.unicodeScalars.allSatisfy {
            ("0"..."9").contains($0) || ("a"..."z").contains($0) || ("A"..."Z").contains($0)
                || $0 == "." || $0 == "-" || $0 == "+"
        }
        return allowed && !version.isEmpty && version.count <= 40 ? version : nil
    }
}

/// `crabrix.ai.recentLessons.v1`: the last lessons opened in Learn, newest
/// first, at most 10. Recorded only while a learning link is connected; the
/// app has no other record of which lesson was opened last.
struct RecentLessonsStore {
    static let key = "crabrix.ai.recentLessons.v1"
    let defaults: UserDefaults

    func load() -> [AILearningLessonRef] {
        guard let entries = defaults.array(forKey: Self.key) as? [[String: String]] else { return [] }
        return entries.compactMap { entry in
            guard let course = entry["courseId"], let lesson = entry["lessonId"],
                  AILearningState.isIdentifier(course), AILearningState.isIdentifier(lesson) else { return nil }
            return AILearningLessonRef(courseId: course, lessonId: lesson)
        }
    }

    /// Returns whether the list changed.
    @discardableResult
    func record(_ lesson: AILearningLessonRef) -> Bool {
        guard AILearningState.isIdentifier(lesson.courseId), AILearningState.isIdentifier(lesson.lessonId) else {
            return false
        }
        let current = load()
        guard current.first != lesson else { return false }
        let updated = ([lesson] + current.filter { $0.lessonId != lesson.lessonId })
            .prefix(LearningLinkSnapshot.maximumRecentLessons)
        defaults.set(updated.map { ["courseId": $0.courseId, "lessonId": $0.lessonId] }, forKey: Self.key)
        return true
    }

    func clear() { defaults.removeObject(forKey: Self.key) }
}
