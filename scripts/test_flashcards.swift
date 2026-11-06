import Foundation
import SQLite3

/// Fast, real SQLite checks, also runnable without booting Simulator.
@main
struct FlashcardStorageChecks {
    static func card(_ id: String = "one", answer: String = "A borrowed view") -> Flashcard {
        Flashcard(id: "ownership/\(id)/concept", courseID: "ownership", courseTitle: "Ownership",
                  lessonID: id, lessonTitle: "Borrowing", kind: .concept,
                  prompt: "What is a borrow?", answer: answer, code: nil)
    }

    static func sql(_ sql: String, url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw FlashcardStoreError.unavailable }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw FlashcardStoreError.unavailable }
    }

    static func check(_ condition: Bool, _ message: String = "Check failed") {
        precondition(condition, message)
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "crabrix-card-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "reviews.sqlite")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let database = try FlashcardReviewDatabase(url: url)
        let first = card()
        let again = try database.review(card: first, grade: .again, eventID: "attempt-1", now: now)
        check(again.mastery.incorrect == 1 && again.mastery.correct == 0)
        check(abs(again.mastery.dueAt.timeIntervalSince(now) - 600) < 0.01)
        let duplicate = try database.review(card: first, grade: .again, eventID: "attempt-1", now: now)
        check(duplicate == again, "Duplicate tap must not reschedule")
        do {
            _ = try database.review(card: first, grade: .easy, eventID: "attempt-1", now: now)
            preconditionFailure("An event ID must not be reused with a different grade")
        } catch {}
        check(try database.records()[first.id] == again)
        let secondConnection = try FlashcardReviewDatabase(url: url)
        check(try secondConnection.records()[first.id] == again, "History survives connection recreation")

        let easyCard = card("two", answer: "Independent owned data")
        let easy = try database.review(card: easyCard, grade: .easy, eventID: "easy-1", now: now)
        check(easy.mastery.dueAt.timeIntervalSince(now) == 4 * 86_400)
        let hard = try database.review(card: card("three"), grade: .hard, eventID: "hard-1", now: now)
        check(hard.mastery.dueAt.timeIntervalSince(now) == 86_400)
        let learned = FlashcardDeck.learned([first, easyCard], completedLessonIDs: [first.lessonID])
        check(learned.map(\.id) == [first.id])
        check(FlashcardReviewQueue.due([first], records: try database.records(), now: now).isEmpty)
        let changed = card(answer: "A reference, without transferring ownership")
        check(FlashcardReviewQueue.due([changed], records: try database.records(), now: now).count == 1)
        let changedReview = try database.review(card: changed, grade: .easy, eventID: "new-content", now: now)
        check(changedReview.mastery.incorrect == 1 && changedReview.mastery.correct == 1)
        check(changedReview.mastery.repetitions == 1 && changedReview.revision == changed.revision)

        let before = try database.records()
        try sql("CREATE TRIGGER reject_card BEFORE INSERT ON cards BEGIN SELECT RAISE(FAIL, 'fixture failure'); END", url: url)
        do {
            _ = try database.review(card: card("four"), grade: .easy, eventID: "failed-write", now: now)
            preconditionFailure("The injected write failure must be reported")
        } catch {}
        check(try database.records() == before, "Failed write must roll back the full transaction")
        try sql("DROP TRIGGER reject_card", url: url)
        let retry = try database.review(card: card("four"), grade: .easy, eventID: "failed-write", now: now)
        check(retry.mastery.correct == 1, "A failed transaction must not consume the attempt ID")

        var invalid = retry
        invalid.mastery.easeFactor = .nan
        let beforeRestore = try database.records()
        do { try database.replace(records: [invalid]); preconditionFailure("Reject invalid backup") } catch {}
        check(try database.records() == beforeRestore)
        try database.replace(records: Array(before.values))
        check(try database.records() == before)

        try sql("PRAGMA user_version=2", url: url)
        do { _ = try FlashcardReviewDatabase(url: url); preconditionFailure("Preserve newer schemas") }
        catch FlashcardStoreError.unsupportedVersion {}
        check(try database.records() == before, "Forward-version rejection must not erase history")
        print("PASS: SQLite persistence, idempotency, rollback/retry, schedules, learned filtering, content updates and safe restore")
    }
}
