import Foundation

enum LearningProgressKeys {
    static let progress = "crabrix.progress.state.v1"
    static let completed = "crabrix.learn.completedLessonIDs"
    static let answers = "crabrix.learn.lessonAnswerIndices"
    static let mastery = "crabrix.mastery.v1"
    static let resetDates = "crabrix.learn.lessonResetDates.v1"
    static let terms = "crabrix.learn.trainingSessions"
    static let recall = "crabrix.learn.recallSessions"
    static let cards = "crabrix.learn.flashcardSessions"
    static let restoreGeneration = "crabrix.learning.restoreGeneration.v1"
}

/// Reading legacy formats is deliberate: adding cards must not reset the three
/// established drills or migrate unrelated preferences, projects and tokens.
enum LearningProgressPreferences {
    static func captureBase(defaults: UserDefaults, deviceFamily: String, now: Date = Date()) throws -> LearningProgressSnapshot {
        let progress = try data(defaults, key: LearningProgressKeys.progress)
            ?? JSONEncoder().encode(CrabrixProgressState())
        let masteryData = try data(defaults, key: LearningProgressKeys.mastery)
        if let masteryData { try LearningBackupCodec.checkJSONBudget(masteryData) }
        let mastery = try masteryData.map { try JSONDecoder().decode([String: TopicMasteryRecord].self, from: $0) } ?? [:]
        let completed: [String]
        if defaults.object(forKey: LearningProgressKeys.completed) == nil { completed = [] }
        else if let value = defaults.stringArray(forKey: LearningProgressKeys.completed) { completed = value }
        else { throw LearningBackupError.invalid }
        if defaults.object(forKey: LearningProgressKeys.answers) != nil,
           defaults.dictionary(forKey: LearningProgressKeys.answers) == nil { throw LearningBackupError.invalid }
        let rawAnswers = defaults.dictionary(forKey: LearningProgressKeys.answers) ?? [:]
        let answers = rawAnswers.compactMapValues { ($0 as? NSNumber)?.intValue }
        guard answers.count == rawAnswers.count else { throw LearningBackupError.invalid }
        let resets: [String: Double]
        if defaults.object(forKey: LearningProgressKeys.resetDates) == nil { resets = [:] }
        else if let values = defaults.dictionary(forKey: LearningProgressKeys.resetDates) as? [String: Double] { resets = values }
        else { throw LearningBackupError.invalid }
        return LearningProgressSnapshot(
            schemaVersion: 1, id: UUID().uuidString, createdAt: now, deviceFamily: deviceFamily,
            progressData: progress, completedLessonIDs: completed, answers: answers,
            mastery: mastery, flashcards: [], lessonResetDates: resets,
            termTrainSessions: defaults.integer(forKey: LearningProgressKeys.terms),
            codeRecallSessions: defaults.integer(forKey: LearningProgressKeys.recall),
            flashcardSessions: defaults.integer(forKey: LearningProgressKeys.cards)
        )
    }

    static func apply(_ snapshot: LearningProgressSnapshot, generation: String, defaults: UserDefaults, domain: String) throws {
        let snapshot = try snapshot.validated()
        var values = defaults.persistentDomain(forName: domain) ?? [:]
        // The entire preference-domain update keeps unrelated keys as they are.
        // Only this explicit learning allowlist comes from the selected backup.
        values[LearningProgressKeys.progress] = snapshot.progressData
        values[LearningProgressKeys.completed] = snapshot.completedLessonIDs
        values[LearningProgressKeys.answers] = snapshot.answers
        values[LearningProgressKeys.mastery] = try JSONEncoder().encode(snapshot.mastery)
        values[LearningProgressKeys.resetDates] = snapshot.lessonResetDates
        values[LearningProgressKeys.terms] = snapshot.termTrainSessions
        values[LearningProgressKeys.recall] = snapshot.codeRecallSessions
        values[LearningProgressKeys.cards] = snapshot.flashcardSessions
        values[LearningProgressKeys.restoreGeneration] = generation
        defaults.setPersistentDomain(values, forName: domain)
        // This one explicit recovery transaction needs a durable boundary before
        // its journal is removed; ordinary progress writes remain unchanged.
        guard defaults.synchronize() else { throw LearningBackupError.preferencesNotSaved }
    }

    private static func data(_ defaults: UserDefaults, key: String) throws -> Data? {
        guard let value = defaults.object(forKey: key) else { return nil }
        guard let data = value as? Data else { throw LearningBackupError.invalid }
        return data
    }
}

/// A restore is journalled before either persistence format is changed. An app
/// interruption can finish the same operation on launch, before stores cache it.
struct LearningRestoreJournal: Codable {
    let id: String
    let encodedSnapshot: Data
}

enum LearningProgressArchive {
    static func directory() throws -> URL {
        try FlashcardReviewDatabase.defaultURL().deletingLastPathComponent()
    }

    static func capture(defaults: UserDefaults, database: FlashcardReviewDatabase,
                        deviceFamily: String, now: Date = Date()) throws -> LearningProgressSnapshot {
        var snapshot = try LearningProgressPreferences.captureBase(defaults: defaults, deviceFamily: deviceFamily, now: now)
        snapshot.flashcards = try database.records().values.sorted { $0.cardID < $1.cardID }
        return try snapshot.validated()
    }

    static func stageRestore(_ encoded: Data, previous: LearningProgressSnapshot, directory: URL) throws -> String {
        let snapshot = try LearningBackupCodec.decode(encoded)
        let canonical = try LearningBackupCodec.encode(snapshot)
        let rollback = try LearningBackupCodec.encode(previous)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try rollback.write(to: directory.appending(path: "Before restore.crabrixprogress"), options: .atomic)
        let journal = LearningRestoreJournal(id: UUID().uuidString, encodedSnapshot: canonical)
        let bytes = try JSONEncoder().encode(journal)
        var journalURL = directory.appending(path: "restore-journal.json")
        try bytes.write(to: journalURL, options: .atomic)
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try journalURL.setResourceValues(resources)
        return journal.id
    }

    /// Explicit recovery fallback. Keep both the previous known-good snapshot
    /// and the interrupted journal before staging a return to previous progress.
    static func stagePreviousProgress(directory: URL) throws {
        let previous = try LearningBackupCodec.readFile(directory.appending(path: "Before restore.crabrixprogress"))
        let canonical = try LearningBackupCodec.encode(LearningBackupCodec.decode(previous))
        let journalURL = directory.appending(path: "restore-journal.json")
        if FileManager.default.fileExists(atPath: journalURL.path) {
            let size = try journalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 8 * 1_024 * 1_024 else { throw LearningBackupError.tooLarge }
            try Data(contentsOf: journalURL).write(to: directory.appending(path: "Interrupted restore.journal"), options: .atomic)
        }
        let journal = LearningRestoreJournal(id: UUID().uuidString, encodedSnapshot: canonical)
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
    }

    @discardableResult
    static func recoverPendingRestore(defaults: UserDefaults, domain: String,
                                      directory: URL? = nil, database: FlashcardReviewDatabase? = nil) throws -> Bool {
        let directory = try directory ?? self.directory()
        let url = directory.appending(path: "restore-journal.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        // Base64 journal overhead is bounded separately from a user backup file.
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 8 * 1_024 * 1_024 else { throw LearningBackupError.tooLarge }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 8 * 1_024 * 1_024 else { throw LearningBackupError.tooLarge }
        try LearningBackupCodec.checkJSONBudget(bytes, maximumBytes: 8 * 1_024 * 1_024)
        let journal = try JSONDecoder().decode(LearningRestoreJournal.self, from: bytes)
        guard UUID(uuidString: journal.id) != nil else { throw LearningBackupError.invalid }
        let snapshot = try LearningBackupCodec.decode(journal.encodedSnapshot)
        if defaults.string(forKey: LearningProgressKeys.restoreGeneration) != journal.id {
            let database = try database ?? FlashcardReviewDatabase(url: directory.appending(path: "flashcards.sqlite"))
            try database.replace(records: snapshot.flashcards)
            try LearningProgressPreferences.apply(snapshot, generation: journal.id, defaults: defaults, domain: domain)
        }
        // A matching durable generation means recovery must not replay an old
        // snapshot over reviews earned after a previous successful restore.
        try FileManager.default.removeItem(at: url)
        return true
    }
}
