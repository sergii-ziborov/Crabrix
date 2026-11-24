import Foundation

/// The installed lessons a tutor message may point at, from the course
/// repository. Built on demand; never stored.
struct LearningLinkCatalog: Equatable, Sendable {
    struct Course: Equatable, Sendable {
        let id: String
        let title: String
        let version: String?
        let lessonIDs: [String]
    }

    let courses: [Course]
    /// lesson ID → installed course ID.
    let lessonCourse: [String: String]
    let lessonTitles: [String: String]

    init(courses: [Course], lessonTitles: [String: String] = [:]) {
        self.courses = courses
        var map: [String: String] = [:]
        for course in courses {
            for lesson in course.lessonIDs where map[lesson] == nil { map[lesson] = course.id }
        }
        lessonCourse = map
        self.lessonTitles = lessonTitles
    }

    init(repository: InstalledCourseRepository) {
        var titles: [String: String] = [:]
        let courses = repository.courses.filter { $0.id != "examples" }.map { course in
            let lessons = course.units.flatMap(\.lessons)
            for lesson in lessons where titles[lesson.id] == nil { titles[lesson.id] = lesson.title }
            return Course(id: course.id, title: course.title,
                          version: repository.loaded[course.id]?.contentVersion,
                          lessonIDs: lessons.map(\.id))
        }
        self.init(courses: courses.filter { !$0.lessonIDs.isEmpty }, lessonTitles: titles)
    }

    var installedCourseIDs: Set<String> { Set(courses.map(\.id)) }

    enum LessonCheck: Equatable {
        /// In an installed course: it opens with the app's own navigation.
        case installed
        /// Its course is not installed here, so the lesson cannot be checked or
        /// opened yet; the card asks the learner to download the course.
        case courseNotInstalled
        case unknown
    }

    func check(courseID: String, lessonID: String) -> LessonCheck {
        guard AILearningState.isIdentifier(courseID), AILearningState.isIdentifier(lessonID) else { return .unknown }
        if let owner = lessonCourse[lessonID] { return owner == courseID ? .installed : .unknown }
        return installedCourseIDs.contains(courseID) ? .unknown : .courseNotInstalled
    }
}

/// `crabrix.tutor-message` v1 after validation: only fields that passed, as
/// plain text. Written by the MCP server for the agent; nothing in it can mark
/// progress, and the app never follows it as an instruction or a link.
struct TutorMessage: Equatable, Sendable {
    enum Kind: String, Sendable { case assign, focus }

    struct Lesson: Equatable, Sendable {
        let courseId: String
        let lessonId: String
        let reason: String?
    }

    let kind: Kind
    let createdAt: Date
    let lessons: [Lesson]
    let pathId: String?
    let goal: String?
    let concepts: [String]
    let note: String?
    let agent: String?
}

enum TutorMessageValidator {
    static let format = "crabrix.tutor-message"
    static let schemaVersion = 1
    static let maximumPlaintextBytes = 8 * 1_024
    static let maximumLessons = 5
    static let reasonLimit = 200
    static let goalLimit = 300
    static let conceptLimit = 80
    static let maximumConcepts = 10
    static let noteLimit = 500
    static let agentLimit = 60

    enum Rejection: Error, Equatable {
        case tooLarge
        case notJSON
        case wrongFormat
        case unknownKind
        case invalidDate
        case tooManyLessons
        case noValidLessons
        case nothingValid
    }

    /// Strict on structure (format, version, kind, date, lesson count), lenient
    /// per field: an invalid field is dropped and the rest is kept.
    static func validate(_ data: Data, catalog: LearningLinkCatalog,
                         now: Date = Date()) -> Result<TutorMessage, Rejection> {
        guard data.count <= maximumPlaintextBytes else { return .failure(.tooLarge) }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return .failure(.notJSON) }
        guard root["format"] as? String == format,
              let version = root["schemaVersion"] as? NSNumber, !isBoolean(version),
              version.doubleValue == Double(schemaVersion) else { return .failure(.wrongFormat) }
        guard let kindText = root["kind"] as? String, let kind = TutorMessage.Kind(rawValue: kindText) else {
            return .failure(.unknownKind)
        }
        guard let createdText = root["createdAt"] as? String, let created = parseDate(createdText) else {
            return .failure(.invalidDate)
        }
        let createdAt = min(created, now)
        let note = plainText(root["note"], limit: noteLimit)
        let agent = plainText(root["agent"], limit: agentLimit)

        switch kind {
        case .assign:
            guard let raw = root["lessons"] as? [Any], !raw.isEmpty else { return .failure(.noValidLessons) }
            guard raw.count <= maximumLessons else { return .failure(.tooManyLessons) }
            var seen = Set<String>()
            let lessons = raw.compactMap { item -> TutorMessage.Lesson? in
                guard let entry = item as? [String: Any],
                      let courseID = entry["courseId"] as? String,
                      let lessonID = entry["lessonId"] as? String,
                      catalog.check(courseID: courseID, lessonID: lessonID) != .unknown,
                      seen.insert(lessonID).inserted
                else { return nil }
                return .init(courseId: courseID, lessonId: lessonID,
                             reason: plainText(entry["reason"], limit: reasonLimit))
            }
            guard !lessons.isEmpty else { return .failure(.noValidLessons) }
            return .success(TutorMessage(kind: .assign, createdAt: createdAt, lessons: lessons, pathId: nil,
                                         goal: nil, concepts: [], note: note, agent: agent))
        case .focus:
            let pathID = (root["pathId"] as? String).flatMap { isPathID($0) ? $0 : nil }
            let goal = plainText(root["goal"], limit: goalLimit)
            var concepts: [String] = []
            if let raw = root["concepts"] as? [Any], raw.count <= maximumConcepts {
                var seen = Set<String>()
                concepts = raw.compactMap { plainText($0, limit: conceptLimit) }
                    .filter { seen.insert($0.lowercased()).inserted }
            }
            guard pathID != nil || goal != nil || !concepts.isEmpty || note != nil else {
                return .failure(.nothingValid)
            }
            return .success(TutorMessage(kind: .focus, createdAt: createdAt, lessons: [], pathId: pathID,
                                         goal: goal, concepts: concepts, note: note, agent: agent))
        }
    }

    /// One line of plain text within `limit` code points, normalised exactly
    /// like the SDK's `plainText` (hidden characters become spaces, runs of
    /// white space one space, trimmed), so what the app stores and echoes in
    /// the snapshot always passes the MCP server's checks. Shown verbatim:
    /// never as Markdown, a link or an instruction.
    static func plainText(_ value: Any?, limit: Int) -> String? {
        guard let text = value as? String, text.unicodeScalars.count <= limit * 4 else { return nil }
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if isHidden(scalar) || scalar.properties.isWhitespace {
                pendingSpace = !scalars.isEmpty
            } else {
                if pendingSpace { scalars.append(" ") }
                pendingSpace = false
                scalars.append(scalar)
            }
        }
        guard !scalars.isEmpty, scalars.count <= limit else { return nil }
        return String(scalars)
    }

    /// The SDK's hidden set: control characters and the marks that can reorder
    /// or hide displayed text (U+200D, which joins emoji, stays).
    private static func isHidden(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F, 0x200B, 0x200C, 0x200E, 0x200F, 0x2028, 0x2029,
             0x202A...0x202E, 0x2060...0x2064, 0x2066...0x2069, 0xFEFF: true
        default: false
        }
    }

    /// A learning path id as the SDK reads it: `^[a-z0-9-]{1,128}$`.
    static func isPathID(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        return (1...128).contains(scalars.count) && scalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-"
        }
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    static func parseDate(_ text: String) -> Date? {
        guard text.count <= 40 else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

/// What the app accepted from the learner's AI tutor, `crabrix.ai.tutorPlan.v1`:
/// at most 20 assigned lessons (newest first) and the latest focus. Local only;
/// the snapshot echoes it so the agent sees its own plan.
struct TutorPlan: Codable, Equatable, Sendable {
    struct Assignment: Codable, Equatable, Sendable, Identifiable {
        let courseId: String
        let lessonId: String
        let reason: String?
        let assignedAt: Date
        let agent: String?

        var id: String { lessonId }
    }

    struct Focus: Codable, Equatable, Sendable {
        let pathId: String?
        let goal: String?
        let concepts: [String]
        let note: String?
        let agent: String?
        let updatedAt: Date
    }

    struct Note: Codable, Equatable, Sendable {
        let text: String
        let agent: String?
        let createdAt: Date
    }

    static let maximumAssignments = 20
    /// Inbox IDs already applied, so a message that is fetched again (its
    /// acknowledgement failed) is not applied twice.
    static let rememberedMessages = 100

    var schemaVersion = 1
    var assignments: [Assignment] = []
    var focus: Focus?
    /// The latest note that came with an assignment.
    var note: Note?
    var appliedMessageIDs: [String] = []

    static let empty = TutorPlan()

    var isEmpty: Bool { assignments.isEmpty && focus == nil && note == nil }

    /// Returns false when the message was already applied.
    @discardableResult
    mutating func apply(_ message: TutorMessage, messageID: String? = nil) -> Bool {
        if let messageID {
            guard !appliedMessageIDs.contains(messageID) else { return false }
            appliedMessageIDs.append(messageID)
            appliedMessageIDs = Array(appliedMessageIDs.suffix(Self.rememberedMessages))
        }
        switch message.kind {
        case .assign:
            let fresh = message.lessons.map {
                Assignment(courseId: $0.courseId, lessonId: $0.lessonId, reason: $0.reason,
                           assignedAt: message.createdAt, agent: message.agent)
            }
            let freshIDs = Set(fresh.map(\.lessonId))
            let merged = fresh + assignments.filter { !freshIDs.contains($0.lessonId) }
            // Newest first; a message keeps its own order.
            assignments = merged.enumerated()
                .sorted { $0.element.assignedAt == $1.element.assignedAt
                    ? $0.offset < $1.offset : $0.element.assignedAt > $1.element.assignedAt }
                .prefix(Self.maximumAssignments)
                .map(\.element)
            if let text = message.note, note.map({ $0.createdAt <= message.createdAt }) ?? true {
                note = Note(text: text, agent: message.agent, createdAt: message.createdAt)
            }
        case .focus:
            guard focus.map({ $0.updatedAt <= message.createdAt }) ?? true else { return true }
            focus = Focus(pathId: message.pathId, goal: message.goal, concepts: message.concepts,
                          note: message.note, agent: message.agent, updatedAt: message.createdAt)
        }
        return true
    }

    mutating func dismiss(lessonID: String) {
        assignments.removeAll { $0.lessonId == lessonID }
    }

    mutating func clearFocus() {
        focus = nil
        note = nil
    }

    /// Done only when the app's own completion contains the lesson.
    func openAssignments(completed: Set<String>) -> [Assignment] {
        assignments.filter { !completed.contains($0.lessonId) }
    }

    func doneCount(completed: Set<String>) -> Int {
        assignments.filter { completed.contains($0.lessonId) }.count
    }
}

/// `crabrix.ai.tutorPlan.v1` in the standard defaults (a test passes its own).
struct TutorPlanStore {
    static let key = "crabrix.ai.tutorPlan.v1"
    let defaults: UserDefaults

    func load() -> TutorPlan {
        guard let data = defaults.data(forKey: Self.key), data.count <= 256 * 1_024,
              let plan = try? Self.decoder.decode(TutorPlan.self, from: data) else { return .empty }
        return plan
    }

    func save(_ plan: TutorPlan) {
        if plan.isEmpty && plan.appliedMessageIDs.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? Self.encoder.encode(plan) {
            defaults.set(data, forKey: Self.key)
        }
    }

    func clear() { defaults.removeObject(forKey: Self.key) }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
