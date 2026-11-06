import XCTest
@testable import Crabrix

final class LearningBackupTests: XCTestCase {
    private func snapshot() throws -> LearningProgressSnapshot {
        var progress = CrabrixProgressState()
        progress.totalPoints = 120
        progress.lessonsCompleted = 1
        progress.rustLessonsCompleted = 1
        progress.processedEventKeys = ["lesson:borrowing:first-completion"]
        return LearningProgressSnapshot(schemaVersion: 1, id: UUID().uuidString,
            createdAt: Date(), deviceFamily: "iPhone", progressData: try JSONEncoder().encode(progress),
            completedLessonIDs: ["borrowing"], answers: ["borrowing": 1], mastery: [:], flashcards: [],
            lessonResetDates: [:], termTrainSessions: 3, codeRecallSessions: 2, flashcardSessions: 1)
    }

    func testRoundTripAndStableContentIdentity() throws {
        let original = try snapshot().validated()
        let data = try LearningBackupCodec.encode(original)
        XCTAssertEqual(try LearningBackupCodec.decode(data), original)
        var other = original
        other.id = UUID().uuidString
        other.createdAt = Date().addingTimeInterval(60)
        other.deviceFamily = "iPad"
        XCTAssertEqual(try original.contentHash(), try other.contentHash())
        other.answers["borrowing"] = 2
        XCTAssertNotEqual(try original.contentHash(), try other.contentHash())
    }

    func testRejectsCorruptionBombsInvalidAndFutureData() throws {
        let data = try LearningBackupCodec.encode(snapshot())
        var corrupt = data
        corrupt[corrupt.count - 1] ^= 0xFF
        XCTAssertThrowsError(try LearningBackupCodec.decode(corrupt))
        XCTAssertThrowsError(try LearningBackupCodec.decode(data.prefix(20)))
        XCTAssertThrowsError(try LearningBackupCodec.decode(Data(repeating: 0, count: LearningBackupCodec.maximumEncodedBytes + 1)))
        XCTAssertThrowsError(try LearningBackupCodec.checkJSONBudget(Data((String(repeating: "[", count: 33) + String(repeating: "]", count: 33)).utf8)))
        var future = try snapshot()
        future.schemaVersion = 2
        XCTAssertThrowsError(try LearningBackupCodec.encode(future))
        future.schemaVersion = 1
        future.answers["borrowing"] = -1
        XCTAssertThrowsError(try LearningBackupCodec.encode(future))
        // Delimiters inside strings must not be mistaken for structural nesting.
        XCTAssertNoThrow(try LearningBackupCodec.checkJSONBudget(Data("{\"term\":\"[[[\\\"{}\"}".utf8)))
    }

    func testInterruptedRestoreRecoversBothFormatsPreservesOtherPreferencesAndIsNotReplayed() throws {
        let domain = "CrabrixBackupTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let root = FileManager.default.temporaryDirectory.appending(path: domain)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try FlashcardReviewDatabase(url: root.appending(path: "flashcards.sqlite"))
        defaults.set("dark", forKey: "crabrix.appearance")
        defaults.set("private-local-value", forKey: "unrelated-private-setting")
        let before = try LearningProgressArchive.capture(defaults: defaults, database: db, deviceFamily: "iPad")
        var target = try snapshot()
        let card = Flashcard(id: "ownership/borrowing/concept", courseID: "ownership", courseTitle: "Ownership",
                             lessonID: "borrowing", lessonTitle: "Borrowing", kind: .concept,
                             prompt: "What is borrowed?", answer: "A reference", code: nil)
        var record = FlashcardReviewRecord(card: card, now: Date())
        record.review(.hard, card: card, now: Date())
        target.flashcards = [record]
        let generation = try LearningProgressArchive.stageRestore(LearningBackupCodec.encode(target), previous: before, directory: root)
        let journal = root.appending(path: "restore-journal.json")
        let savedJournal = try Data(contentsOf: journal)
        XCTAssertEqual(defaults.stringArray(forKey: LearningProgressKeys.completed), nil, "Staging alone must not change progress")
        XCTAssertTrue(try LearningProgressArchive.recoverPendingRestore(defaults: defaults, domain: domain, directory: root, database: db))
        XCTAssertEqual(defaults.stringArray(forKey: LearningProgressKeys.completed), ["borrowing"])
        XCTAssertEqual(try db.records()[card.id], record)
        XCTAssertEqual(defaults.string(forKey: "crabrix.appearance"), "dark")
        XCTAssertEqual(defaults.string(forKey: "unrelated-private-setting"), "private-local-value")
        XCTAssertEqual(defaults.string(forKey: LearningProgressKeys.restoreGeneration), generation)
        XCTAssertEqual(try LearningBackupCodec.decode(LearningBackupCodec.readFile(root.appending(path: "Before restore.crabrixprogress"))), before)
        // Simulate termination after commit but before journal cleanup. Later
        // learning must survive recovery of the already-committed generation.
        defaults.set(["borrowing", "lifetimes"], forKey: LearningProgressKeys.completed)
        try savedJournal.write(to: journal)
        XCTAssertTrue(try LearningProgressArchive.recoverPendingRestore(defaults: defaults, domain: domain, directory: root, database: db))
        XCTAssertEqual(defaults.stringArray(forKey: LearningProgressKeys.completed), ["borrowing", "lifetimes"])
        XCTAssertFalse(try LearningProgressArchive.recoverPendingRestore(defaults: defaults, domain: domain, directory: root, database: db))
    }

    func testInvalidImportDoesNotChangeExistingHistory() throws {
        let domain = "CrabrixBackupReject.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(["existing"], forKey: LearningProgressKeys.completed)
        let root = FileManager.default.temporaryDirectory.appending(path: domain)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try LearningProgressPreferences.captureBase(defaults: defaults, deviceFamily: "iPad")
        XCTAssertThrowsError(try LearningProgressArchive.stageRestore(Data("invalid".utf8), previous: before, directory: root))
        XCTAssertEqual(defaults.stringArray(forKey: LearningProgressKeys.completed), ["existing"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "restore-journal.json").path))
    }

    func testCorruptInterruptedJournalCanReturnToPreviousKnownGoodProgress() throws {
        let domain = "CrabrixBackupFallback.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appending(path: domain)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: root) }
        let db = try FlashcardReviewDatabase(url: root.appending(path: "flashcards.sqlite"))
        defaults.set(["previous-lesson"], forKey: LearningProgressKeys.completed)
        let before = try LearningProgressArchive.capture(defaults: defaults, database: db, deviceFamily: "iPad")
        _ = try LearningProgressArchive.stageRestore(LearningBackupCodec.encode(snapshot()), previous: before, directory: root)
        let corrupt = Data("interrupted and damaged journal".utf8)
        try corrupt.write(to: root.appending(path: "restore-journal.json"))
        XCTAssertThrowsError(try LearningProgressArchive.recoverPendingRestore(defaults: defaults, domain: domain, directory: root, database: db))
        try LearningProgressArchive.stagePreviousProgress(directory: root)
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "Interrupted restore.journal")), corrupt)
        XCTAssertTrue(try LearningProgressArchive.recoverPendingRestore(defaults: defaults, domain: domain, directory: root, database: db))
        XCTAssertEqual(defaults.stringArray(forKey: LearningProgressKeys.completed), ["previous-lesson"])
        XCTAssertEqual(try db.records().count, 0)
    }
}
