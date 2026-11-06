import CryptoKit
import Foundation

/// A view of signed lesson content, not another independently maintained syllabus.
/// Identity survives course updates; revision changes when the actual card changes.
struct Flashcard: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case concept, question, term }

    let id: String
    let courseID: String
    let courseTitle: String
    let lessonID: String
    let lessonTitle: String
    let kind: Kind
    let prompt: String
    let answer: String
    let code: String?

    let revision: String

    init(id: String, courseID: String, courseTitle: String, lessonID: String,
         lessonTitle: String, kind: Kind, prompt: String, answer: String, code: String?) {
        self.id = id
        self.courseID = courseID
        self.courseTitle = courseTitle
        self.lessonID = lessonID
        self.lessonTitle = lessonTitle
        self.kind = kind
        self.prompt = prompt
        self.answer = answer
        self.code = code
        let bytes = (try? JSONEncoder().encode([prompt, answer, code ?? ""])) ?? Data()
        revision = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

enum FlashcardGrade: Int, Codable, CaseIterable, Sendable {
    case again = 1
    case hard = 3
    case easy = 5

    var title: String {
        switch self {
        case .again: "Don’t know"
        case .hard: "Hard"
        case .easy: "Easy"
        }
    }
}

enum FlashcardDeck {
    static let sessionSize = 12
    static let maximumCards = 4_096

    /// Only completed lessons enter the personal deck. Removing a downloaded
    /// course hides its cards without deleting their durable review history.
    static func learned(_ cards: [Flashcard], completedLessonIDs: Set<String>) -> [Flashcard] {
        cards.filter { completedLessonIDs.contains($0.lessonID) }
    }

}
