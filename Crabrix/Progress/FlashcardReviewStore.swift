import Foundation
import SQLite3

struct FlashcardReviewRecord: Codable, Equatable, Sendable {
    let cardID: String
    let lessonID: String
    var revision: String
    var mastery: TopicMasteryRecord

    init(card: Flashcard, now: Date) {
        cardID = card.id
        lessonID = card.lessonID
        revision = card.revision
        mastery = TopicMasteryRecord(topic: card.id, now: now)
    }

    mutating func review(_ grade: FlashcardGrade, card: Flashcard, now: Date) {
        if revision != card.revision {
            // A changed answer needs a fresh schedule, not erased lifetime stats.
            let correct = mastery.correct, incorrect = mastery.incorrect
            mastery = TopicMasteryRecord(topic: cardID, now: now)
            mastery.correct = correct
            mastery.incorrect = incorrect
            revision = card.revision
        }
        mastery.record(quality: grade.rawValue, now: now)
        mastery.easeFactor = min(20, mastery.easeFactor)
        if grade == .again {
            mastery.intervalDays = 10.0 / 1_440
        } else if grade == .hard {
            mastery.intervalDays = min(mastery.intervalDays, 1)
        } else if mastery.repetitions == 1 {
            mastery.intervalDays = 4
        }
        mastery.intervalDays = min(3_650, mastery.intervalDays)
        mastery.dueAt = now.addingTimeInterval(mastery.intervalDays * 86_400)
    }

    var isValid: Bool {
        !cardID.isEmpty && cardID.utf8.count <= 256 && !cardID.contains("\0")
            && !lessonID.isEmpty && lessonID.utf8.count <= 128
            && revision.utf8.count == 64 && revision.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && mastery.topic == cardID && (0...100_000_000).contains(mastery.repetitions)
            && mastery.correct >= 0 && mastery.incorrect >= 0
            && mastery.correct <= 100_000_000 && mastery.incorrect <= 100_000_000
            && mastery.easeFactor.isFinite && (1.3...20).contains(mastery.easeFactor)
            && mastery.intervalDays.isFinite && (0...3_650).contains(mastery.intervalDays)
            && (0...7_258_118_400).contains(mastery.dueAt.timeIntervalSince1970)
            && (mastery.lastSeenAt.map { (0...7_258_118_400).contains($0.timeIntervalSince1970) } ?? true)
    }
}

enum FlashcardReviewQueue {
    static func due(_ cards: [Flashcard], records: [String: FlashcardReviewRecord], now: Date) -> [Flashcard] {
        cards.filter { card in
            guard let record = records[card.id] else { return true }
            return record.revision != card.revision || record.mastery.isDue(at: now)
        }
    }

    /// A session does not ask a lesson's fact and immediately reveal its quiz.
    /// Repeated generic answers from related Atlas steps are separated as well.
    static func session(
        from cards: [Flashcard], records: [String: FlashcardReviewRecord],
        now: Date, limit: Int = FlashcardDeck.sessionSize,
        using generator: inout some RandomNumberGenerator
    ) -> [Flashcard] {
        var pool = due(cards, records: records, now: now)
        var selected: [Flashcard] = []
        while selected.count < max(0, limit), !pool.isEmpty {
            let weights = pool.map { card -> Double in
                if let old = records[card.id], old.revision != card.revision { return 6 }
                return TopicScheduler.weight(for: records[card.id]?.mastery, now: now)
            }
            let total = weights.reduce(0, +)
            var roll = Double.random(in: 0..<total, using: &generator)
            var chosen = pool.count - 1
            for index in pool.indices {
                roll -= weights[index]
                if roll < 0 { chosen = index; break }
            }
            let card = pool[chosen]
            selected.append(card)
            pool.removeAll { $0.lessonID == card.lessonID || $0.answer == card.answer }
        }
        return selected
    }
}

enum FlashcardStoreError: LocalizedError {
    case unavailable, unsupportedVersion, invalidRecord
    var errorDescription: String? {
        switch self {
        case .unavailable: "Review history could not be saved. Your existing learning progress is unchanged."
        case .unsupportedVersion: "This review history was created by a newer Crabrix version. Update Crabrix to open it."
        case .invalidRecord: "The review history is invalid. It has been kept for recovery."
        }
    }
}

/// A small independent database; existing lesson/rating formats are not migrated.
/// One lock owns the connection. Callers can do I/O away from the main actor.
final class FlashcardReviewDatabase: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    static let maximumRecords = 4_096

    static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appending(path: "Crabrix/Learning/flashcards.sqlite")
    }

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.deletingLastPathComponent().path)
        #endif
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            connection = nil
            throw FlashcardStoreError.unavailable
        }
        do {
            sqlite3_busy_timeout(connection, 1_500)
            let version = try integer("PRAGMA user_version")
            guard version <= 1 else { throw FlashcardStoreError.unsupportedVersion }
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("CREATE TABLE IF NOT EXISTS cards (id TEXT PRIMARY KEY, payload BLOB NOT NULL CHECK(length(payload) <= 8192))")
            try execute("CREATE TABLE IF NOT EXISTS review_events (id TEXT PRIMARY KEY, card_id TEXT NOT NULL, revision TEXT NOT NULL, grade INTEGER NOT NULL, reviewed_at REAL NOT NULL)")
            if version == 0 { try execute("PRAGMA user_version=1") }
        } catch {
            if let connection { sqlite3_close(connection) }
            connection = nil
            throw error
        }
    }

    deinit { if let connection { sqlite3_close(connection) } }

    func records() throws -> [String: FlashcardReviewRecord] {
        lock.lock(); defer { lock.unlock() }
        return try readRecords()
    }

    /// One UI attempt has one id even if two taps or a retry arrive together.
    /// The schedule and its deduplication receipt commit in the same transaction.
    @discardableResult
    func review(card: Flashcard, grade: FlashcardGrade, eventID: String, now: Date) throws -> FlashcardReviewRecord {
        lock.lock(); defer { lock.unlock() }
        guard !eventID.isEmpty, eventID.utf8.count <= 128, !eventID.contains("\0") else { throw FlashcardStoreError.invalidRecord }
        try execute("BEGIN IMMEDIATE")
        do {
            let existing = try readRecords()
            var record = existing[card.id] ?? FlashcardReviewRecord(card: card, now: now)
            let statement = try prepare("INSERT OR IGNORE INTO review_events (id, card_id, revision, grade, reviewed_at) VALUES (?, ?, ?, ?, ?)")
            defer { sqlite3_finalize(statement) }
            bind(eventID, to: statement, index: 1)
            bind(card.id, to: statement, index: 2)
            bind(card.revision, to: statement, index: 3)
            sqlite3_bind_int(statement, 4, Int32(grade.rawValue))
            sqlite3_bind_double(statement, 5, now.timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw FlashcardStoreError.unavailable }
            if sqlite3_changes(connection) > 0 {
                guard existing[card.id] != nil || existing.count < Self.maximumRecords else { throw FlashcardStoreError.invalidRecord }
                record.review(grade, card: card, now: now)
                try write(record)
                try execute("DELETE FROM review_events WHERE id IN (SELECT id FROM review_events ORDER BY reviewed_at DESC, id DESC LIMIT -1 OFFSET 10000)")
            } else {
                let receipt = try prepare("SELECT card_id, revision, grade FROM review_events WHERE id=?")
                defer { sqlite3_finalize(receipt) }
                bind(eventID, to: receipt, index: 1)
                guard sqlite3_step(receipt) == SQLITE_ROW,
                      let savedID = sqlite3_column_text(receipt, 0),
                      let savedRevision = sqlite3_column_text(receipt, 1),
                      String(cString: savedID) == card.id,
                      String(cString: savedRevision) == card.revision,
                      sqlite3_column_int(receipt, 2) == grade.rawValue else { throw FlashcardStoreError.invalidRecord }
            }
            try execute("COMMIT")
            return record
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Logical snapshots avoid copying a live SQLite file without its WAL.
    /// The backup coordinator can retain the old snapshot before a restore.
    func replace(records: [FlashcardReviewRecord]) throws {
        lock.lock(); defer { lock.unlock() }
        guard records.count <= Self.maximumRecords,
              Set(records.map(\.cardID)).count == records.count,
              records.allSatisfy(\.isValid) else { throw FlashcardStoreError.invalidRecord }
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM cards")
            try execute("DELETE FROM review_events")
            for record in records { try write(record) }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func readRecords() throws -> [String: FlashcardReviewRecord] {
        let statement = try prepare("SELECT id, payload FROM cards LIMIT 4097")
        defer { sqlite3_finalize(statement) }
        var records: [String: FlashcardReviewRecord] = [:]
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW, records.count < Self.maximumRecords,
                  let idBytes = sqlite3_column_text(statement, 0),
                  let bytes = sqlite3_column_blob(statement, 1) else { throw FlashcardStoreError.invalidRecord }
            let size = Int(sqlite3_column_bytes(statement, 1))
            guard (1...8_192).contains(size) else { throw FlashcardStoreError.invalidRecord }
            let record = try JSONDecoder().decode(FlashcardReviewRecord.self, from: Data(bytes: bytes, count: size))
            let id = String(cString: idBytes)
            guard record.isValid, record.cardID == id else { throw FlashcardStoreError.invalidRecord }
            records[id] = record
        }
        return records
    }

    private func write(_ record: FlashcardReviewRecord) throws {
        guard record.isValid else { throw FlashcardStoreError.invalidRecord }
        let data = try JSONEncoder().encode(record)
        guard data.count <= 8_192 else { throw FlashcardStoreError.invalidRecord }
        let statement = try prepare("INSERT INTO cards (id, payload) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(statement) }
        bind(record.cardID, to: statement, index: 1)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw FlashcardStoreError.unavailable }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FlashcardStoreError.unavailable
        }
        return statement
    }

    private func bind(_ string: String, to statement: OpaquePointer, index: Int32) {
        _ = string.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw FlashcardStoreError.unavailable }
    }

    private func integer(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw FlashcardStoreError.unavailable }
        return Int(sqlite3_column_int(statement, 0))
    }
}
