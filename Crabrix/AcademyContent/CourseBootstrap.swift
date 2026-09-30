import CryptoKit
import Foundation

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

    func activateBundledBaseline() async throws -> InstalledCourseRepository {
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
        return try InstalledCourseRepository(
            root: root, records: await installer.installed(), keyring: keyring
        )
    }

    func loadInstalled() async throws -> InstalledCourseRepository {
        let installer = try CourseInstaller(root: root, appVersion: appVersion)
        return try InstalledCourseRepository(
            root: root, records: await installer.installed(), keyring: keyring()
        )
    }

    func keyring() throws -> CourseKeyring {
        guard let packs = bundle.url(forResource: "MigrationCoursePacks", withExtension: nil)
        else { throw CoursePackError.manifestMismatch("bundled keyring") }
        return try JSONDecoder().decode(
            CourseKeyring.self,
            from: Data(contentsOf: packs.appending(path: "production-keyring.json"))
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
