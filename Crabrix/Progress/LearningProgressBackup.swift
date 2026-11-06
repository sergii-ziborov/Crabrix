import Compression
import CryptoKit
import Foundation

enum LearningBackupError: LocalizedError {
    case invalid, newerVersion, tooLarge, unavailable, preferencesNotSaved
    var errorDescription: String? {
        switch self {
        case .invalid: "This is not a valid Crabrix learning backup. Your progress has not been replaced."
        case .newerVersion: "This backup needs a newer Crabrix version. Update Crabrix before restoring it."
        case .tooLarge: "This learning backup exceeds the supported size. Your existing progress is kept."
        case .unavailable: "The learning backup could not be read or saved. Please try again."
        case .preferencesNotSaved: "The restore could not finish saving. Crabrix will retry recovery on the next launch."
        }
    }
}

/// Only learning state belongs here. No project files, credentials, room keys,
/// compiler caches, local execution permissions or editable lesson source.
struct LearningProgressSnapshot: Codable, Equatable, Sendable, Identifiable {
    var schemaVersion: Int
    var id: String
    var createdAt: Date
    var deviceFamily: String
    var progressData: Data
    var completedLessonIDs: [String]
    var answers: [String: Int]
    var mastery: [String: TopicMasteryRecord]
    var flashcards: [FlashcardReviewRecord]
    var lessonResetDates: [String: Double]
    var termTrainSessions: Int
    var codeRecallSessions: Int
    var flashcardSessions: Int

    var hasProgress: Bool {
        !completedLessonIDs.isEmpty || !flashcards.isEmpty
            || mastery.values.contains { $0.attempts > 0 }
            || ((try? JSONDecoder().decode(CrabrixProgressState.self, from: progressData).totalPoints) ?? 0) > 0
    }

    /// Metadata changes must not create an automatic-backup feedback loop.
    func contentHash() throws -> String {
        var content = self
        content.id = ""
        content.createdAt = Date(timeIntervalSince1970: 0)
        content.deviceFamily = ""
        return SHA256.hash(data: try LearningBackupCodec.json(content)).map { String(format: "%02x", $0) }.joined()
    }

    func validated() throws -> Self {
        guard schemaVersion <= 1 else { throw LearningBackupError.newerVersion }
        guard schemaVersion == 1 else { throw LearningBackupError.invalid }
        guard UUID(uuidString: id) != nil,
              (0...7_258_118_400).contains(createdAt.timeIntervalSince1970),
              deviceFamily.utf8.count <= 80,
              progressData.count <= 524_288,
              completedLessonIDs.count <= 10_000,
              Set(completedLessonIDs).count == completedLessonIDs.count,
              completedLessonIDs.allSatisfy(Self.validID),
              answers.count <= 10_000,
              answers.allSatisfy({ Self.validID($0.key) && (0...100).contains($0.value) }),
              mastery.count <= 10_000,
              flashcards.count <= FlashcardReviewDatabase.maximumRecords,
              Set(flashcards.map(\.cardID)).count == flashcards.count,
              flashcards.allSatisfy(\.isValid),
              lessonResetDates.count <= 10_000,
              lessonResetDates.allSatisfy({ Self.validID($0.key) && $0.value.isFinite && (0...7_258_118_400).contains($0.value) }),
              [termTrainSessions, codeRecallSessions, flashcardSessions].allSatisfy({ (0...1_000_000_000).contains($0) }) else {
            throw LearningBackupError.invalid
        }
        try LearningBackupCodec.checkJSONBudget(progressData)
        let progress = try JSONDecoder().decode(CrabrixProgressState.self, from: progressData)
        guard progress.version == CrabrixProgressState.currentVersion else { throw LearningBackupError.newerVersion }
        let counters = [progress.totalPoints, progress.lessonsCompleted, progress.rustLessonsCompleted,
                        progress.algorithmStudySteps, progress.buildsSucceeded, progress.linesChanged,
                        progress.diagnosticsRepaired, progress.practiceRoundsPassed, progress.termTrainRuns,
                        progress.termTrainPairsMatched, progress.termTrainBestStreak, progress.bestTimedPairsPerMinute,
                        progress.packagesCompiled, progress.codeRecallRuns, progress.codeRecallBestLevel,
                        progress.codeRecallLines, progress.charactersTyped, progress.achievementCatalogVersion]
        guard counters.allSatisfy({ (0...1_000_000_000).contains($0) }),
              progress.processedEventKeys.count <= 20_000,
              progress.processedEventKeys.allSatisfy(Self.validID),
              progress.recentBuildRevisions.count <= 10_000,
              progress.recentBuildRevisions.allSatisfy(Self.validID),
              progress.solvedAlgorithmPatternIDs.count <= 10_000,
              progress.solvedAlgorithmPatternIDs.allSatisfy(Self.validID),
              progress.unlockedAchievementIDs.count <= 10_000,
              progress.unlockedAchievementIDs.allSatisfy(Self.validID),
              progress.achievementMethods.count <= 128,
              progress.achievementMethods.reduce(0, { $0 + $1.patternIDs.count }) <= 4_096,
              progress.achievementMethods.allSatisfy({
                  Self.validID($0.id) && $0.title.utf8.count <= 200 && $0.subtitle.utf8.count <= 500
                      && $0.systemImage.utf8.count <= 80 && $0.achievementTitle.utf8.count <= 200
                      && $0.patternIDs.allSatisfy(Self.validID)
              }),
              [progress.lastRunRewardDay, progress.lastActiveAt, progress.rewardDay].allSatisfy({
                  $0.map { (0...7_258_118_400).contains($0.timeIntervalSince1970) } ?? true
              }),
              progress.dailyRewardPoints.count <= 100,
              progress.dailyRewardPoints.keys.allSatisfy(Self.validID),
              progress.dailyRewardPoints.values.allSatisfy({ (0...1_000_000).contains($0) }),
              progress.trainingBestPoints.count <= 10_000,
              progress.trainingBestPoints.keys.allSatisfy(Self.validID),
              progress.trainingBestPoints.values.allSatisfy({ (0...1_000_000).contains($0) }) else { throw LearningBackupError.invalid }
        var normalized = self
        normalized.completedLessonIDs.sort()
        normalized.flashcards.sort { $0.cardID < $1.cardID }
        for (id, var record) in mastery {
            guard Self.validID(id), record.topic == id,
                  record.correct >= 0, record.incorrect >= 0,
                  record.correct <= 100_000_000, record.incorrect <= 100_000_000,
                  record.repetitions >= 0, record.repetitions <= 100_000_000,
                  record.easeFactor.isFinite, record.easeFactor >= 1.3, record.easeFactor <= 20,
                  record.intervalDays.isFinite, record.intervalDays >= 0,
                  record.dueAt.timeIntervalSince1970.isFinite,
                  record.lastSeenAt.map({ (0...7_258_118_400).contains($0.timeIntervalSince1970) }) ?? true else { throw LearningBackupError.invalid }
            // Old SM-2 histories could grow an interval far beyond a lifetime.
            // Preserve attempts while bounding the schedule in a restored copy.
            if record.intervalDays > 3_650 {
                record.intervalDays = 3_650
                record.dueAt = (record.lastSeenAt ?? createdAt).addingTimeInterval(3_650 * 86_400)
            }
            guard (0...7_258_118_400).contains(record.dueAt.timeIntervalSince1970) else { throw LearningBackupError.invalid }
            normalized.mastery[id] = record
        }
        // Re-encode the known model so unknown data cannot hide in opaque bytes.
        guard var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(progress)) as? [String: Any] else {
            throw LearningBackupError.invalid
        }
        for key in ["processedEventKeys", "solvedAlgorithmPatternIDs", "unlockedAchievementIDs"] {
            if let values = object[key] as? [String] { object[key] = values.sorted() }
        }
        normalized.progressData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard normalized.progressData.count <= 524_288 else { throw LearningBackupError.tooLarge }
        return normalized
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && !value.contains("\0")
    }
}

enum LearningBackupCodec {
    static let maximumDecodedBytes = 4 * 1_024 * 1_024
    static let maximumEncodedBytes = 5 * 1_024 * 1_024
    static let maximumCloudBytes = 200 * 1_024
    private static let magic = Data("CRABRIX-PROGRESS/1\n".utf8)

    static func json(_ snapshot: LearningProgressSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func encode(_ snapshot: LearningProgressSnapshot) throws -> Data {
        let bytes = try json(snapshot.validated())
        guard bytes.count <= maximumDecodedBytes else { throw LearningBackupError.tooLarge }
        var compressed = Data(count: maximumEncodedBytes)
        let count = compressed.withUnsafeMutableBytes { output in
            bytes.withUnsafeBytes { input in
                compression_encode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
                                          input.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0 else { throw LearningBackupError.tooLarge }
        compressed.count = count
        var encoded = magic
        var size = UInt32(bytes.count).bigEndian
        withUnsafeBytes(of: &size) { encoded.append(contentsOf: $0) }
        encoded.append(contentsOf: SHA256.hash(data: bytes))
        encoded.append(compressed)
        guard encoded.count <= maximumEncodedBytes else { throw LearningBackupError.tooLarge }
        return encoded
    }

    static func decode(_ encoded: Data) throws -> LearningProgressSnapshot {
        let header = magic.count + 4 + 32
        guard encoded.count <= maximumEncodedBytes else { throw LearningBackupError.tooLarge }
        guard encoded.count > header, encoded.prefix(magic.count) == magic else { throw LearningBackupError.invalid }
        let size = encoded[magic.count..<(magic.count + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= maximumDecodedBytes else { throw LearningBackupError.tooLarge }
        var bytes = Data(count: Int(size) + 1)
        let compressed = encoded.dropFirst(header)
        let count = bytes.withUnsafeMutableBytes { output in
            compressed.withUnsafeBytes { input in
                compression_decode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
                                          input.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard count == Int(size) else { throw LearningBackupError.invalid }
        bytes.count = count
        guard Data(SHA256.hash(data: bytes)) == encoded[(magic.count + 4)..<header] else { throw LearningBackupError.invalid }
        try checkJSONBudget(bytes)
        return try JSONDecoder().decode(LearningProgressSnapshot.self, from: bytes).validated()
    }

    /// Bound nesting and collection tokens before the general-purpose decoder.
    /// Quoted code/IDs do not count as structural JSON delimiters.
    static func checkJSONBudget(_ bytes: Data, maximumBytes: Int = maximumDecodedBytes) throws {
        guard bytes.count <= maximumBytes else { throw LearningBackupError.tooLarge }
        var depth = 0, tokens = 0
        var quoted = false, escaped = false
        for byte in bytes {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 {
                depth += 1; tokens += 1
                guard depth <= 32 else { throw LearningBackupError.invalid }
            } else if byte == 125 || byte == 93 {
                depth -= 1
                guard depth >= 0 else { throw LearningBackupError.invalid }
            } else if byte == 44 || byte == 58 { tokens += 1 }
            guard tokens <= 200_000 else { throw LearningBackupError.tooLarge }
        }
        guard depth == 0, !quoted else { throw LearningBackupError.invalid }
    }

    static func readFile(_ url: URL) throws -> Data {
        guard let stream = InputStream(url: url) else { throw LearningBackupError.unavailable }
        stream.open(); defer { stream.close() }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw LearningBackupError.unavailable }
            if count == 0 { break }
            guard result.count + count <= maximumEncodedBytes else { throw LearningBackupError.tooLarge }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}
