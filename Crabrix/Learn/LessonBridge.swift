import Foundation

/// A lesson for developers who arrive from another language: one habit from
/// that language next to its Rust equivalent, and the existing Academy lessons
/// this bridge already taught and checked.
struct LessonBridge: Equatable, Sendable {
    enum Language: String, Sendable {
        case c
        case javascript
        case typescript

        /// Picks the highlighter; C has no web grammar in the app.
        var snippetPath: String {
            switch self {
            case .c: "snippet.c"
            case .javascript: "snippet.js"
            case .typescript: "snippet.ts"
            }
        }
    }

    struct Contrast: Equatable, Sendable {
        let from: String
        let rust: String
    }

    struct CreditTarget: Hashable, Sendable {
        let courseID: String
        let lessonID: String
    }

    let from: Language
    let fromLabel: String
    let fromCode: String
    let fromCaption: String
    let contrasts: [Contrast]
    let credits: [CreditTarget]
}

/// Transport form of the optional `bridge` lesson object (`bridge-lessons-v1`).
struct CourseBridgeDTO: Decodable, Sendable {
    struct Contrast: Decodable, Sendable {
        let from: String
        let rust: String
    }

    let from: String
    let fromLabel: String
    let fromCode: String
    let fromCaption: String
    let contrasts: [Contrast]
    let credits: [String]

    static let capability = "bridge-lessons-v1"

    /// Bounds are looser than the authoring contract so that an editorial
    /// change does not need an app update, but still refuse a pack that could
    /// only have been produced by mistake.
    func runtimeBridge(courseID: String, lessonID: String) throws -> LessonBridge {
        guard let language = LessonBridge.Language(rawValue: from) else {
            throw CoursePackError.incompatibleCapability("bridge language \(from)")
        }
        func filled(_ value: String, limit: Int) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= limit
        }
        guard filled(fromLabel, limit: 60), !fromLabel.contains("\n"),
              filled(fromCode, limit: 8_000),
              fromCode.split(separator: "\n", omittingEmptySubsequences: false).count <= 60,
              filled(fromCaption, limit: 600),
              (1...6).contains(contrasts.count),
              contrasts.allSatisfy({ filled($0.from, limit: 400) && filled($0.rust, limit: 400) }),
              credits.count <= 8 else {
            throw CoursePackError.manifestMismatch("bridge \(lessonID)")
        }
        var targets: [LessonBridge.CreditTarget] = []
        for credit in credits {
            let parts = credit.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2,
                  Self.isIdentifier(parts[0]), Self.isIdentifier(parts[1]),
                  parts[0] != courseID, parts[1] != lessonID else {
                throw CoursePackError.manifestMismatch("bridge credit \(lessonID)")
            }
            let target = LessonBridge.CreditTarget(courseID: parts[0], lessonID: parts[1])
            guard !targets.contains(target) else {
                throw CoursePackError.manifestMismatch("duplicate bridge credit \(lessonID)")
            }
            targets.append(target)
        }
        return LessonBridge(
            from: language, fromLabel: fromLabel, fromCode: fromCode, fromCaption: fromCaption,
            contrasts: contrasts.map { .init(from: $0.from, rust: $0.rust) }, credits: targets
        )
    }

    private static func isIdentifier(_ value: String) -> Bool {
        guard (1...128).contains(value.utf8.count), value != ".", value != ".." else { return false }
        return value.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
                || $0 == "-" || $0 == "_" || $0 == "."
        }
    }
}

/// Credits are the second way a lesson can be done: a completed bridge lesson
/// vouches for lessons whose rule it already taught and checked. They count for
/// the course path, never for rating or achievements, and a credited lesson
/// becomes an ordinary completion once the learner finishes it themselves.
enum LessonCredits {
    /// Completed or credited: what unlocking, course progress, Continue
    /// learning and Flashcards treat as done.
    static func learned(completed: Set<String>, credited: [String: String]) -> Set<String> {
        completed.union(credited.keys)
    }

    /// Lesson IDs a completed bridge lesson credits, limited to installed
    /// courses. A target in a course that is not installed is simply skipped.
    static func targets(for bridge: LessonBridge?, courses: [RustCourse]) -> [String] {
        guard let bridge else { return [] }
        return bridge.credits.compactMap { target in
            guard let course = courses.first(where: { $0.id == target.courseID }),
                  course.units.contains(where: { unit in unit.lessons.contains { $0.id == target.lessonID } })
            else { return nil }
            return target.lessonID
        }
    }

    /// The credit map after `lessonID` is really completed.
    static func completing(
        _ lessonID: String, targets: [String],
        completed: Set<String>, credited: [String: String]
    ) -> [String: String] {
        var updated = credited
        // Finishing a credited lesson yourself turns it into a regular completion.
        updated[lessonID] = nil
        for target in targets where target != lessonID
            && !completed.contains(target) && updated[target] == nil {
            updated[target] = lessonID
        }
        return updated
    }

    /// The credit map after the lessons in `lessonIDs` are reset.
    ///
    /// Resetting a course clears credits on its own lessons, and resetting a
    /// bridge course revokes what its lessons granted. Another completed bridge
    /// lesson that also vouches for a revoked target keeps it known, but never
    /// for a lesson the learner just chose to restart.
    static func afterReset(
        _ lessonIDs: Set<String>, completed: Set<String>, credited: [String: String],
        creditTargets: (String) -> [String]
    ) -> [String: String] {
        var updated = credited.filter { !lessonIDs.contains($0.key) && !lessonIDs.contains($0.value) }
        let remaining = completed.subtracting(lessonIDs)
        for source in remaining.sorted() {
            for target in creditTargets(source) where !lessonIDs.contains(target)
                && !remaining.contains(target) && updated[target] == nil {
                updated[target] = source
            }
        }
        return updated
    }

    /// "Rust for C Developers" → "Known from C".
    static func knownLabel(forCourseTitle title: String?) -> String {
        guard let title, !title.isEmpty else { return "Known from a bridge course" }
        let prefix = "Rust for ", suffix = " Developers"
        if title.hasPrefix(prefix), title.hasSuffix(suffix), title.count > prefix.count + suffix.count {
            return "Known from " + title.dropFirst(prefix.count).dropLast(suffix.count)
        }
        return "Known from \(title)"
    }

    /// Defaults may contain anything; keep only well-formed string pairs.
    static func decode(_ value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        return dictionary.compactMapValues { $0 as? String }
            .filter { !$0.key.isEmpty && !$0.value.isEmpty && $0.key != $0.value }
    }
}
