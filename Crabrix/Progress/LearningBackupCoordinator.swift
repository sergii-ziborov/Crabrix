import Foundation
import SwiftUI
import UIKit

extension Notification.Name {
    static let learningProgressRestored = Notification.Name("Crabrix.learningProgressRestored")
    static let flashcardReviewSaved = Notification.Name("Crabrix.flashcardReviewSaved")
}

@MainActor
protocol LearningCloudStorage {
    var values: [String: Any] { get }
    var notificationObject: AnyObject? { get }
    func set(_ data: Data, forKey key: String)
    func synchronize()
}

@MainActor
final class AppleLearningCloudStorage: LearningCloudStorage {
    private let store = NSUbiquitousKeyValueStore.default
    var values: [String: Any] { store.dictionaryRepresentation }
    var notificationObject: AnyObject? { store }
    func set(_ data: Data, forKey key: String) { store.set(data, forKey: key) }
    func synchronize() { store.synchronize() }
}

/// Apple stores only a bounded, private learning snapshot. Copies from another
/// installation are offered for explicit restore, never merged over local work.
@MainActor
final class LearningBackupCoordinator: ObservableObject {
    @Published private(set) var automatic: Bool
    @Published private(set) var copies: [LearningProgressSnapshot] = []
    @Published private(set) var status = "A local recovery copy is kept on this device."
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private(set) var recoveryRequired: Bool
    var canRestore: () -> Bool = { false }

    private let defaults: UserDefaults
    private let cloud: any LearningCloudStorage
    private let iCloudAvailable: () -> Bool
    private let archiveDirectory: URL?
    private let prefix = "crabrix.learning.backup.v1."
    private let enabledKey = "crabrix.learning.cloudBackup.enabled"
    private let installKey = "crabrix.learning.backup.installID"
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private var cloudHash: String?
    private var localHash: String?
    private var started = false
    private var reviewsInFlight = 0

    init(defaults: UserDefaults = .standard, cloud: (any LearningCloudStorage)? = nil,
         archiveDirectory: URL? = nil,
         iCloudAvailable: @escaping () -> Bool = { FileManager.default.ubiquityIdentityToken != nil },
         recoveryError: String? = nil) {
        self.defaults = defaults
        self.cloud = cloud ?? AppleLearningCloudStorage()
        self.iCloudAvailable = iCloudAvailable
        self.archiveDirectory = archiveDirectory
        automatic = defaults.bool(forKey: enabledKey)
        errorMessage = recoveryError
        recoveryRequired = recoveryError != nil
        if recoveryRequired { status = "An interrupted restore needs attention. Your recovery files have been kept." }
    }

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        for name in [UserDefaults.didChangeNotification, .flashcardReviewSaved] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.schedule() }
            })
        }
        observers.append(center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                            object: cloud.notificationObject, queue: .main) { [weak self] note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            Task { @MainActor in
                guard let self else { return }
                if reason == NSUbiquitousKeyValueStoreAccountChange {
                    self.setAutomatic(false)
                    self.status = "Your iCloud account changed. Enable backup again for this account."
                } else if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
                    self.cloudHash = nil
                    self.status = "iCloud backup storage is full. Export a recovery file to keep another copy."
                }
                self.refreshCopies()
            }
        })
        observers.append(center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.setAutomatic(false)
                self?.status = "iCloud availability changed. Check your Apple account before enabling backup."
                self?.refreshCopies()
            }
        })
        if automatic { cloud.synchronize() }
        refreshCopies()
        schedule()
    }

    func setAutomatic(_ enabled: Bool) {
        automatic = enabled
        defaults.set(enabled, forKey: enabledKey)
        cloudHash = nil
        if !enabled { status = "Automatic iCloud backup is off. Existing recovery copies are kept." }
        if enabled { cloud.synchronize() }
        schedule()
    }

    func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard !isWorking, !recoveryRequired else { return }
        do {
            let snapshot = try capture()
            let hash = try snapshot.contentHash()
            let bytes = try LearningBackupCodec.encode(snapshot)
            if hash != localHash {
                try bytes.write(to: localURL(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                localHash = hash
            }
            guard automatic else { refreshCopies(); return }
            guard iCloudAvailable() else {
                status = "Sign in to iCloud in device Settings. Local progress and file export still work."
                refreshCopies(); return
            }
            guard snapshot.hasProgress else {
                status = "iCloud backup is on. Your first completed lesson will be backed up."
                refreshCopies(); return
            }
            guard bytes.count <= LearningBackupCodec.maximumCloudBytes else {
                status = "This progress history needs a recovery file. Export it to Files or iCloud Drive."
                refreshCopies(); return
            }
            if hash != cloudHash {
                let key = prefix + installID()
                var proposed = cloud.values
                proposed[key] = bytes
                let size = try PropertyListSerialization.data(fromPropertyList: proposed, format: .binary, options: 0).count
                guard size <= 850 * 1_024 else {
                    status = "There isn’t enough iCloud backup space. Export a recovery file instead."
                    refreshCopies(); return
                }
                cloud.set(bytes, forKey: key)
                // This requests synchronization; it is not a server delivery receipt.
                cloud.synchronize()
                cloudHash = hash
                status = "Backup queued for your private iCloud. Apple syncs it when available."
            }
            refreshCopies()
        } catch { errorMessage = error.localizedDescription }
    }

    func refreshCopies() {
        var found: [LearningProgressSnapshot] = []
        if let directory = try? learningDirectory() {
            for name in ["Latest.crabrixprogress", "Before restore.crabrixprogress"] {
                if let local = try? LearningBackupCodec.decode(LearningBackupCodec.readFile(directory.appending(path: name))),
                   local.hasProgress || name == "Before restore.crabrixprogress" {
                    found.append(local)
                }
            }
        }
        if iCloudAvailable() {
            for (key, value) in cloud.values where key.hasPrefix(prefix) {
                guard let bytes = value as? Data, bytes.count <= LearningBackupCodec.maximumCloudBytes,
                      let snapshot = try? LearningBackupCodec.decode(bytes), snapshot.hasProgress else { continue }
                found.append(snapshot)
            }
        }
        var seen = Set<String>()
        copies = found.sorted { $0.createdAt > $1.createdAt }.filter { seen.insert($0.id).inserted }
    }

    func requestRefresh() {
        // Opening recovery on a new installation can fetch existing copies
        // without enabling uploads or replacing a previous installation's key.
        cloud.synchronize()
        refreshCopies()
    }

    func exportData() throws -> Data { try LearningBackupCodec.encode(capture()) }

    func beginReviewWrite() { reviewsInFlight += 1 }
    func endReviewWrite() { reviewsInFlight = max(0, reviewsInFlight - 1) }

    func restore(_ snapshot: LearningProgressSnapshot) throws {
        guard canRestore(), !isWorking, !recoveryRequired, reviewsInFlight == 0 else {
            throw LearningRestoreAvailabilityError.busy
        }
        isWorking = true
        defer { isWorking = false }
        let directory = try learningDirectory()
        let encoded = try LearningBackupCodec.encode(snapshot)
        guard let domain = Bundle.main.bundleIdentifier else { throw LearningBackupError.unavailable }
        do {
            _ = try LearningProgressArchive.stageRestore(encoded, previous: capture(), directory: directory)
            try LearningProgressArchive.recoverPendingRestore(defaults: defaults, domain: domain, directory: directory)
        } catch {
            if FileManager.default.fileExists(atPath: directory.appending(path: "restore-journal.json").path) {
                recoveryRequired = true
                errorMessage = error.localizedDescription
            }
            throw error
        }
        TopicMasteryStore.shared.reloadAfterRestore()
        NotificationCenter.default.post(name: .learningProgressRestored, object: nil)
        localHash = nil
        status = "Learning progress restored. Download any missing courses from Learn."
        schedule()
    }

    func retryRecovery(usePreviousProgress: Bool = false) {
        guard recoveryRequired, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let domain = Bundle.main.bundleIdentifier else { throw LearningBackupError.unavailable }
            let directory = try learningDirectory()
            if usePreviousProgress { try LearningProgressArchive.stagePreviousProgress(directory: directory) }
            try LearningProgressArchive.recoverPendingRestore(defaults: defaults, domain: domain, directory: directory)
            TopicMasteryStore.shared.reloadAfterRestore()
            errorMessage = nil
            recoveryRequired = false
            NotificationCenter.default.post(name: .learningProgressRestored, object: nil)
            localHash = nil
            schedule()
        } catch { errorMessage = error.localizedDescription }
    }

    private func capture() throws -> LearningProgressSnapshot {
        let db = try FlashcardReviewDatabase(url: learningDirectory().appending(path: "flashcards.sqlite"))
        return try LearningProgressArchive.capture(defaults: defaults, database: db,
            deviceFamily: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
    }

    private func installID() -> String {
        if let value = defaults.string(forKey: installKey), UUID(uuidString: value) != nil { return value }
        let value = UUID().uuidString
        defaults.set(value, forKey: installKey)
        return value
    }

    private func localURL() throws -> URL {
        let directory = try learningDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Latest.crabrixprogress")
    }

    private func learningDirectory() throws -> URL {
        try archiveDirectory ?? LearningProgressArchive.directory()
    }
}

enum LearningRestoreAvailabilityError: LocalizedError {
    case busy
    var errorDescription: String? { "Finish the current build, debug session or review save and unlock Crabrix before restoring learning progress." }
}
