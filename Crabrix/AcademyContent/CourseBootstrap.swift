import CryptoKit
import Foundation

enum CourseInitialInstallMode: String {
    case existingLearner
    case newLearner
}

/// Resolve the first-launch path before stores can create new progress records.
/// Persisting the decision also lets a crashed migration resume on the next launch.
enum CourseLaunchPolicy {
    private static let modeKey = "crabrix.academy.initialInstall.v1"
    private static let legacyKeys = [
        "crabrix.progress.state.v1",
        "crabrix.learn.completedLessonIDs",
        "crabrix.learn.lessonAnswerIndices",
        "crabrix.learn.attemptEvidence.v1",
        "crabrix.mastery.v1",
        "crabrix.typing.v2",
        "crabrix.contribution.v2",
        "crabrix.contribution.v3",
        "crabrix.appearance",
        "crabrix.editorFontSize",
        "crabrix.keepAwakeDuringBuild",
        "crabrix.learn.trainingSessions",
        "crabrix.learn.recallSessions"
    ]

    static func resolve(
        defaults: UserDefaults = .standard,
        supportRoot: URL? = nil,
        fileManager: FileManager = .default
    ) -> CourseInitialInstallMode {
        if let saved = defaults.string(forKey: modeKey),
           let mode = CourseInitialInstallMode(rawValue: saved) {
            return mode
        }
        let hasLegacyProgress = legacyKeys.contains { defaults.object(forKey: $0) != nil }
        let root = supportRoot ?? fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appending(path: "Crabrix", directoryHint: .isDirectory)
        let hasLegacyProjects = root.map { root in
            ["project-index.json", "recent-projects.json", "projects"].contains {
                fileManager.fileExists(atPath: root.appending(path: $0).path)
            }
        } ?? false
        let mode: CourseInitialInstallMode = hasLegacyProgress || hasLegacyProjects
            ? .existingLearner : .newLearner
        defaults.set(mode.rawValue, forKey: modeKey)
        return mode
    }
}

/// The transition archive lives in this binary, so an update never needs the
/// removed previous app bundle or a network connection to restore Academy.
struct CourseBootstrap {
    let bundle: Bundle
    let root: URL
    let appVersion: SemanticVersion

    init(bundle: Bundle = .main, root: URL? = nil, appVersion: SemanticVersion? = nil) throws {
        self.bundle = bundle
        if let root {
            self.root = root
        } else {
            guard let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else { throw CoursePackError.invalidCatalog }
            self.root = support.appending(path: "Crabrix/Courses", directoryHint: .isDirectory)
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        self.appVersion = appVersion ?? SemanticVersion(version ?? "0")
            ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }

    func activateBundledBaseline(
        for mode: CourseInitialInstallMode = .existingLearner
    ) async throws -> InstalledCourseRepository {
        // Baseline activation is a one-time migration. A learner can later
        // remove a local copy without the next launch silently restoring it.
        let activationMarker = root.appending(path: "baseline-activation-v1.json")
        if FileManager.default.fileExists(atPath: activationMarker.path) {
            return try await loadInstalled()
        }
        guard let packs = bundle.url(forResource: "MigrationCoursePacks", withExtension: nil)
        else { throw CoursePackError.manifestMismatch("bundled migration packs") }
        let keyring = try JSONDecoder().decode(
            CourseKeyring.self,
            from: Data(contentsOf: packs.appending(path: "production-keyring.json"))
        )
        let catalogBytes = try Data(contentsOf: packs.appending(path: "catalog.v1.json"))
        let catalog = try CoursePackVerifier.catalog(
            bytes: catalogBytes, keyring: keyring, lastAcceptedSequence: 0
        )
        let installer = try CourseInstaller(root: root, appVersion: appVersion)
        let current = try await installer.installed()
        let active = Dictionary(uniqueKeysWithValues: current.map { ("\($0.courseID)|\($0.language)", $0) })

        for entry in catalog.courses {
            // A fresh installation starts with an online catalog. Only a
            // learner upgrading from the Swift catalog receives transition
            // packs automatically, preserving their former offline access.
            if mode == .newLearner { continue }
            let name = try Self.singleComponent(entry.courseID)
            let language = try Self.singleComponent(entry.language)
            let key = "\(name)|\(language)"
            // A newer installed version wins. The baseline is only for users
            // who have no active version yet; it never rolls an update back.
            if active[key] != nil { continue }
            let descriptorURL = packs.appending(path: "\(name).descriptor.json")
            let descriptorBytes = try Data(contentsOf: descriptorURL)
            guard SHA256.hash(data: descriptorBytes).hexString == entry.descriptorSHA256 else {
                throw CoursePackError.archiveDigestMismatch
            }
            let archiveName = try Self.singleComponent(entry.archiveURL.lastPathComponent)
            let archiveURL = packs.appending(path: archiveName)
            _ = try await installer.install(
                descriptorBytes: descriptorBytes, downloadedArchive: archiveURL, keyring: keyring
            )
        }
        let installed = try await installer.installed()
        let marker: [String: Any] = [
            "schemaVersion": 1,
            "initialInstallMode": mode.rawValue,
            "catalogSequence": catalog.sequence,
            "courseDigests": Dictionary(uniqueKeysWithValues: installed.map {
                ("\($0.courseID)|\($0.language)", $0.archiveSHA256)
            })
        ]
        try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
            .write(to: activationMarker, options: .atomic)
        return try await installer.loadRepository(keyring: keyring)
    }

    func loadInstalled() async throws -> InstalledCourseRepository {
        let installer = try CourseInstaller(root: root, appVersion: appVersion)
        return try await installer.loadRepository(keyring: keyring())
    }

    func keyring() throws -> CourseKeyring {
        guard let packs = bundle.url(forResource: "MigrationCoursePacks", withExtension: nil)
        else { throw CoursePackError.manifestMismatch("bundled keyring") }
        return try JSONDecoder().decode(
            CourseKeyring.self,
            from: Data(contentsOf: packs.appending(path: "production-keyring.json"))
        )
    }

    func bundledCatalog() throws -> CourseCatalogPayload {
        guard let packs = bundle.url(forResource: "MigrationCoursePacks", withExtension: nil)
        else { throw CoursePackError.manifestMismatch("bundled catalog") }
        let active = bundle.url(forResource: "ActiveCourseCatalog", withExtension: nil)
            ?? packs
        return try CoursePackVerifier.catalog(
            bytes: Data(contentsOf: active.appending(path: "catalog.v1.json")),
            keyring: keyring(), lastAcceptedSequence: 0
        )
    }

    private static func singleComponent(_ value: String) throws -> String {
        let checked = try CoursePackVerifier.validatedPath(value)
        guard !checked.contains("/") else { throw CoursePackError.unsafeArchive(value) }
        return checked
    }
}

private extension SHA256.Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
