import Foundation

/// The Academy UI can depend on this instead of static Swift content catalogs.
/// Repositories are immutable snapshots; updates create a new snapshot while an
/// open CourseSession continues to retain its old version.
protocol CourseRepository: Sendable {
    var courses: [RustCourse] { get }
    func writing(for lessonID: String) -> RustLessonWriting?
    func depth(for lessonID: String) -> RustLessonDepth?
    func evidence(for lessonID: String) -> LessonEvidence?
    func starterProject(for lessonID: String) -> CourseProjectTemplate?
    func challenge(for lessonID: String) -> AlgorithmChallenge?
    func termPairs() -> [CourseTermPairDTO]
}

extension CourseRepository {
    func course(id: String) -> RustCourse? {
        courses.first { $0.id == id }
    }

    func course(containing lessonID: String) -> RustCourse? {
        courses.first { course in
            course.units.contains { unit in unit.lessons.contains { $0.id == lessonID } }
        }
    }

    func lesson(id: String) -> RustLesson? {
        courses.lazy.flatMap(\.units).flatMap(\.lessons).first { $0.id == id }
    }
}

struct LoadedCourse: Sendable {
    let course: RustCourse
    let order: Int
    let writing: [String: RustLessonWriting]
    let depth: [String: RustLessonDepth]
    let evidence: [String: LessonEvidence]
    let projects: [String: CourseProjectTemplate]
    let challenges: [String: AlgorithmChallenge]
    let terms: [CourseTermPairDTO]
    let contentVersion: String
    let archiveSHA256: String
}
