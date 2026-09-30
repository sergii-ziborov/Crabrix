import Foundation

/// A lesson keeps the exact activated content snapshot it opened with. Catalog
/// refreshes and pack updates can replace the active index without changing an
/// in-progress answer or validator.
struct CourseSession: Sendable {
    let token: UUID
    let courseID: String
    let lessonID: String
    let contentVersion: String
    let archiveSHA256: String
    let repository: InstalledCourseRepository

    init?(lessonID: String, repository: InstalledCourseRepository) {
        guard let course = repository.course(containing: lessonID),
              let loaded = repository.loaded[course.id] else { return nil }
        token = UUID()
        courseID = course.id
        self.lessonID = lessonID
        contentVersion = loaded.contentVersion
        archiveSHA256 = loaded.archiveSHA256
        self.repository = repository
    }
}

struct CourseLessonExecution: Sendable {
    let sessionToken: UUID
    let courseID: String
    let contentVersion: String
    let lesson: RustLesson
    let evidence: LessonEvidence
    let challenge: AlgorithmChallenge?

    init?(lesson: RustLesson, session: CourseSession) {
        guard lesson.id == session.lessonID,
              let evidence = session.repository.evidence(for: lesson.id) else { return nil }
        sessionToken = session.token
        courseID = session.courseID
        contentVersion = session.contentVersion
        self.lesson = lesson
        self.evidence = evidence
        challenge = session.repository.challenge(for: lesson.id)
    }
}
