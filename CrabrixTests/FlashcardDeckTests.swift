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
    }
}
