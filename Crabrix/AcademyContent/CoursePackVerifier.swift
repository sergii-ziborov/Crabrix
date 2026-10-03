import CryptoKit
import Foundation
import ZIPFoundation

enum CoursePackError: Error, LocalizedError {
    case invalidEnvelope
    case untrustedKey
    case invalidSignature
    case invalidCatalog
    case rollback
    case immutableVersionConflict
    case incompatibleCapability(String)
    case archiveDigestMismatch
    case unsafeArchive(String)
    case manifestMismatch(String)
    case sizeLimit

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope: "The course signature envelope is malformed."
        case .untrustedKey: "This course was signed by an unknown publisher key."
        case .invalidSignature: "The course signature could not be verified."
        case .invalidCatalog: "The course catalog is malformed."
        case .rollback: "An older course catalog was rejected."
        case .immutableVersionConflict: "A published course version changed its digest."
        case let .incompatibleCapability(value): "This app does not support \(value)."
        case .archiveDigestMismatch: "The downloaded course does not match its signed descriptor."
        case let .unsafeArchive(path): "The course archive has an unsafe entry: \(path)."
        case let .manifestMismatch(path): "The course inventory does not match: \(path)."
        case .sizeLimit: "The course exceeds the app's download or unpacked size limit."
        }
    }
}

struct CourseKeyring: Decodable, Sendable {
    let keys: [String: String]
}

struct CourseEnvelope: Codable, Sendable {
    let keyID: String
    let payloadBase64: String
    let signatureBase64: String
}

struct CourseDescriptorPayload: Decodable, Sendable {
    let schemaVersion: Int
    let courseID: String
    let language: String
    let contentVersion: String
    let archiveName: String
    let archiveBytes: Int
    let archiveSHA256: String
    let courseDigest: String
    let minimumAppVersion: String
    let requiredCapabilities: [String]
}

struct CourseCatalogPayload: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let courseID: String
        let language: String
        let contentVersion: String
        let descriptorURL: URL
        let descriptorSHA256: String
        let archiveURL: URL
        let archiveSHA256: String
        let archiveBytes: Int
        let minimumAppVersion: String
        let requiredCapabilities: [String]
    }

    let schemaVersion: Int
    let sequence: Int
    let releaseNotes: String
    let courses: [Entry]
}

struct CoursePackManifest: Decodable, Sendable {
    struct File: Decodable, Sendable {
        let path: String
        let bytes: Int
        let sha256: String
    }
    let schemaVersion: Int
    let courseID: String
    let language: String
    let contentVersion: String
    let files: [File]
}

struct VerifiedCoursePack: Sendable {
    let descriptor: CourseDescriptorPayload
    let descriptorBytes: Data
    let keyID: String
    let manifest: CoursePackManifest
    let archiveURL: URL
}

enum CoursePackVerifier {
    static let descriptorDomain = Data("Crabrix.CourseDescriptor.v1\n".utf8)
    static let catalogDomain = Data("Crabrix.CourseCatalog.v1\n".utf8)
    static let maximumArchiveBytes = 64 * 1024 * 1024
    static let maximumUnpackedBytes = 128 * 1024 * 1024
    static let maximumFileBytes = 16 * 1024 * 1024
    static let maximumEntries = 5_000

    static func signedPayload(_ bytes: Data, domain: Data, keyring: CourseKeyring) throws -> (Data, String) {
        guard let envelope = try? JSONDecoder().decode(CourseEnvelope.self, from: bytes),
              let payload = Data(base64Encoded: envelope.payloadBase64),
              let signature = Data(base64Encoded: envelope.signatureBase64)
        else { throw CoursePackError.invalidEnvelope }
        guard let rawKey = keyring.keys[envelope.keyID].flatMap({ Data(base64Encoded: $0) }),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
        else { throw CoursePackError.untrustedKey }
        guard key.isValidSignature(signature, for: domain + payload) else {
            throw CoursePackError.invalidSignature
        }
        return (payload, envelope.keyID)
    }

    static func catalog(
        bytes: Data,
        keyring: CourseKeyring,
        lastAcceptedSequence: Int,
        acceptedVersions: [String: String] = [:]
    ) throws -> CourseCatalogPayload {
        let (payload, _) = try signedPayload(bytes, domain: catalogDomain, keyring: keyring)
        guard let catalog = try? JSONDecoder().decode(CourseCatalogPayload.self, from: payload),
              catalog.schemaVersion == 1, catalog.sequence > 0
        else { throw CoursePackError.invalidCatalog }
        guard catalog.sequence > lastAcceptedSequence else { throw CoursePackError.rollback }
        var versions = acceptedVersions
        var inThisCatalog = Set<String>()
        for course in catalog.courses {
            let identity = "\(course.courseID)|\(course.language)|\(course.contentVersion)"
            guard inThisCatalog.insert(identity).inserted else {
                throw CoursePackError.invalidCatalog
            }
            if let existing = versions[identity], existing != course.archiveSHA256 {
                throw CoursePackError.immutableVersionConflict
            }
            versions[identity] = course.archiveSHA256
            guard course.descriptorURL.scheme == "https", course.archiveURL.scheme == "https",
                  course.archiveBytes > 0 else { throw CoursePackError.invalidCatalog }
        }
        return catalog
    }

    static func verify(
        descriptorBytes: Data,
        archiveURL: URL,
        keyring: CourseKeyring
    ) throws -> VerifiedCoursePack {
        let (payload, keyID) = try signedPayload(descriptorBytes, domain: descriptorDomain, keyring: keyring)
        guard let descriptor = try? JSONDecoder().decode(CourseDescriptorPayload.self, from: payload),
              descriptor.schemaVersion == 1, descriptor.archiveName == archiveURL.lastPathComponent,
              descriptor.archiveBytes > 0, descriptor.archiveBytes <= maximumArchiveBytes
        else { throw CoursePackError.invalidEnvelope }
        try checkCapabilities(descriptor.requiredCapabilities)
        let archiveData = try Data(contentsOf: archiveURL, options: [.mappedIfSafe])
        guard archiveData.count == descriptor.archiveBytes,
              SHA256.hash(data: archiveData).hex == descriptor.archiveSHA256
        else { throw CoursePackError.archiveDigestMismatch }
        let archive = try Archive(url: archiveURL, accessMode: .read)
        var actual: [String: (Int, String)] = [:]
        var folded = Set<String>()
        var total = 0
        var manifestData = Data()
        var count = 0
        for entry in archive {
            count += 1
            guard count <= maximumEntries else { throw CoursePackError.sizeLimit }
            let path = try validatedPath(entry.path)
            guard entry.type == .file, !isForbiddenPayload(path) || path == "manifest.json" else {
                throw CoursePackError.unsafeArchive(path)
            }
            let collision = path.precomposedStringWithCanonicalMapping.folding(
                options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
            )
            guard folded.insert(collision).inserted else { throw CoursePackError.unsafeArchive(path) }
            guard entry.uncompressedSize <= maximumFileBytes else { throw CoursePackError.sizeLimit }
            total += Int(entry.uncompressedSize)
            guard total <= maximumUnpackedBytes else { throw CoursePackError.sizeLimit }
            var actualBytes = 0
            var digest = SHA256()
            _ = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
                actualBytes += chunk.count
                guard actualBytes <= maximumFileBytes,
                      actualBytes <= Int(entry.uncompressedSize) else { throw CoursePackError.sizeLimit }
                digest.update(data: chunk)
                if path == "manifest.json" { manifestData.append(chunk) }
            }
            guard UInt64(actualBytes) == entry.uncompressedSize else {
                throw CoursePackError.manifestMismatch(path)
            }
            actual[path] = (actualBytes, digest.finalize().hex)
        }
        guard let manifest = try? JSONDecoder().decode(CoursePackManifest.self, from: manifestData),
              manifest.schemaVersion == 1,
              manifest.courseID == descriptor.courseID,
              manifest.language == descriptor.language,
              manifest.contentVersion == descriptor.contentVersion
        else { throw CoursePackError.manifestMismatch("manifest.json") }
        actual.removeValue(forKey: "manifest.json")
        guard manifest.files.count == actual.count else { throw CoursePackError.manifestMismatch("file count") }
        var paths = Set<String>()
        for file in manifest.files {
            let path = try validatedPath(file.path)
            guard path != "manifest.json", paths.insert(path).inserted,
                  let value = actual[path], value.0 == file.bytes, value.1 == file.sha256
            else { throw CoursePackError.manifestMismatch(path) }
        }
        return VerifiedCoursePack(descriptor: descriptor, descriptorBytes: descriptorBytes,
                                  keyID: keyID, manifest: manifest, archiveURL: archiveURL)
    }

    static func validatedPath(_ path: String) throws -> String {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".." || $0.hasSuffix(".") || $0.hasSuffix(" ")
              }) else { throw CoursePackError.unsafeArchive(path) }
        return path
    }

    private static func isForbiddenPayload(_ path: String) -> Bool {
        let lowered = path.lowercased()
        let forbidden = [".dylib", ".framework", ".wasm", ".rlib", ".rmeta", ".swift", ".js", ".bc", ".so", ".a"]
        return lowered.split(separator: "/").contains { component in
            forbidden.contains { component.hasSuffix($0) }
        }
    }

    private static func checkCapabilities(_ values: [String]) throws {
        for value in values where !CourseCompatibility.supportedCapabilities.contains(value) {
            throw CoursePackError.incompatibleCapability(value)
        }
    }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
