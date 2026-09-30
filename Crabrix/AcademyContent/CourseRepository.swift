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
    func challenge(for lessonID: String) -> CourseChallengeDTO?
    func termPairs() -> [CourseTermPairDTO]
}

struct LoadedCourse: Sendable {
    let course: RustCourse
    let order: Int
    let writing: [String: RustLessonWriting]
    let depth: [String: RustLessonDepth]
    let evidence: [String: LessonEvidence]
    let projects: [String: CourseProjectTemplate]
    let challenges: [String: CourseChallengeDTO]
    let terms: [CourseTermPairDTO]
    let contentVersion: String
    let archiveSHA256: String
}
