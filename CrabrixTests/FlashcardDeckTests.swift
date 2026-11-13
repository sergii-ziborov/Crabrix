import XCTest
@testable import Crabrix

final class FlashcardDeckTests: XCTestCase {
    func testEveryBundledLessonHasCardsAndQuestionsKeepTheirContext() async throws {
        let packs = try XCTUnwrap(Bundle.main.url(forResource: "MigrationCoursePacks", withExtension: nil))
        let keys = try JSONDecoder().decode(CourseKeyring.self, from: Data(contentsOf: packs.appending(path: "production-keyring.json")))
        let root = FileManager.default.temporaryDirectory.appending(path: "FlashcardPacks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1.7"))
        for course in RustCourseCatalog.courses {
            _ = try await installer.install(descriptorBytes: Data(contentsOf: packs.appending(path: "\(course.id).descriptor.json")),
                downloadedArchive: packs.appending(path: "\(course.id)-1.0.1.zip"), keyring: keys)
        }
        let repository = try InstalledCourseRepository(root: root, records: await installer.installed(), keyring: keys)
        let deck = FlashcardDeck.cards(from: repository)
        let lessonIDs = Set(repository.courses.flatMap(\.units).flatMap(\.lessons).map(\.id))
        XCTAssertEqual(Set(deck.map(\.lessonID)), lessonIDs)
        XCTAssertEqual(Set(deck.map(\.id)).count, deck.count)
        XCTAssertTrue(deck.allSatisfy { !$0.answer.isEmpty && !$0.prompt.isEmpty })
        for card in deck where card.kind == .question {
            let writing = try XCTUnwrap(repository.writing(for: card.lessonID))
            XCTAssertTrue(card.answer.hasPrefix(writing.answers[writing.correctAnswer]))
            XCTAssertEqual(card.code ?? "", writing.practiceCode.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let completed = Set(lessonIDs.sorted().prefix(7))
        XCTAssertTrue(FlashcardDeck.learned(deck, completedLessonIDs: completed).allSatisfy { completed.contains($0.lessonID) })
        var rng = SystemRandomNumberGenerator()
        let queue = FlashcardReviewQueue.session(from: deck, records: [:], now: Date(), using: &rng)
        XCTAssertEqual(Set(queue.map(\.lessonID)).count, queue.count)
        XCTAssertEqual(Set(queue.map(\.answer)).count, queue.count)
        XCTAssertLessThanOrEqual(queue.count, 12)
        XCTAssertFalse(deck.contains { $0.prompt.hasPrefix("What is the core idea") })
    }

    /// Release check for signed packs with recall questions, run with
    /// TEST_RUNNER_CRABRIX_RECALL_PACKS pointing at the built packs.
    func testSignedRecallPacksGiveEveryLessonItsOwnQuestions() async throws {
        guard let path = ProcessInfo.processInfo.environment["CRABRIX_RECALL_PACKS"], !path.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_CRABRIX_RECALL_PACKS to run")
        }
        let packs = URL(fileURLWithPath: path)
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "MigrationCoursePacks", withExtension: nil))
        let keys = try JSONDecoder().decode(CourseKeyring.self, from: Data(contentsOf: bundled.appending(path: "production-keyring.json")))
        let root = FileManager.default.temporaryDirectory.appending(path: "RecallPacks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1.9"))
        let names = try FileManager.default.contentsOfDirectory(atPath: path)
        for course in ["algorithms", "basics", "concurrency", "interview", "ownership", "projects", "systems"] {
            let archive = try XCTUnwrap(names.first { $0.hasPrefix(course + "-") && $0.hasSuffix(".zip") })
            _ = try await installer.install(descriptorBytes: Data(contentsOf: packs.appending(path: "\(course).descriptor.json")),
                downloadedArchive: packs.appending(path: archive), keyring: keys)
        }
        let repository = try InstalledCourseRepository(root: root, records: await installer.installed(), keyring: keys)
        let deck = FlashcardDeck.cards(from: repository)
        let lessons = repository.courses.flatMap(\.units).flatMap(\.lessons)
        XCTAssertEqual(lessons.count, 798)
        for lesson in lessons {
            let recall = deck.filter { $0.lessonID == lesson.id && $0.id.contains("/recall-") }
            XCTAssertEqual(recall.count, lesson.id.hasPrefix("algorithm.") ? 1 : 2, lesson.id)
        }
        XCTAssertFalse(deck.contains { $0.prompt.lowercased().contains("core idea") })
    }

    func testRecallQuestionsDecodeAndOlderLessonsStillDecode() throws {
        var lesson: [String: Any] = [
            "summary": "s", "explanation": "e", "exampleCaption": "c", "exampleCode": "", "task": "t",
            "success": "ok", "rule": "r", "practiceCode": "", "question": "q", "answers": ["a", "b"],
            "correctAnswer": 1, "feedback": "f",
        ]
        let older = try JSONDecoder().decode(CourseWritingDTO.self, from: JSONSerialization.data(withJSONObject: lesson))
        XCTAssertEqual(try older.runtimeWriting().recall, [])
        lesson["recall"] = [
            ["question": "Why does `{ base * 2 }` produce a value?", "answer": "Its last expression has no semicolon."],
            ["question": "What type is `value` here?", "answer": "`()`", "code": "let value = { 1; };"],
            ["question": " ", "answer": "dropped"],
        ]
        let newer = try JSONDecoder().decode(CourseWritingDTO.self, from: JSONSerialization.data(withJSONObject: lesson))
        let recall = try newer.runtimeWriting().recall
        XCTAssertEqual(recall.map(\.answer), ["Its last expression has no semicolon.", "`()`"])
        XCTAssertEqual(recall.last?.code, "let value = { 1; };")
    }
}
