import CryptoKit
import Foundation

struct PublisherKeys: Decodable { let keys: [String: String] }
struct SignedEnvelope: Decodable { let keyID: String; let payloadBase64: String; let signatureBase64: String }
struct Catalog: Decodable {
    struct Entry: Decodable {
        let courseID: String
        let descriptorURL: URL
        let archiveURL: URL
        let archiveSHA256: String
        let descriptorSHA256: String
        let archiveBytes: Int
        let requiredCapabilities: [String]
    }
    let schemaVersion: Int
    let sequence: Int
    let courses: [Entry]
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "Crabrix.Catalog", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: message]) }
}
func read(_ url: URL, maximum: Int) throws -> Data {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
    try require(size <= maximum, "Catalog file exceeds its build-time limit")
    let bytes = try Data(contentsOf: url)
    try require(bytes.count <= maximum, "Catalog changed while reading")
    return bytes
}
do {
    let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
    let resources = root.appending(path: "Crabrix/Resources")
    let keys = try JSONDecoder().decode(PublisherKeys.self,
        from: read(resources.appending(path: "MigrationCoursePacks/production-keyring.json"), maximum: 32_768))
    func catalog(_ path: String) throws -> Catalog {
        let envelope = try JSONDecoder().decode(SignedEnvelope.self,
            from: read(resources.appending(path: path), maximum: 256 * 1024))
        guard let payload = Data(base64Encoded: envelope.payloadBase64),
              let signature = Data(base64Encoded: envelope.signatureBase64),
              let publicBytes = keys.keys[envelope.keyID].flatMap({ Data(base64Encoded: $0) })
        else { throw NSError(domain: "Crabrix.Catalog", code: 2) }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
        try require(payload.count <= 192 * 1024 && signature.count == 64
                    && key.isValidSignature(signature, for: Data("Crabrix.CourseCatalog.v1\n".utf8) + payload),
                    "Invalid production publisher signature: \(path)")
        let catalog = try JSONDecoder().decode(Catalog.self, from: payload)
        try require(catalog.schemaVersion == 1 && catalog.sequence > 0, "Unsupported catalog schema")
        for entry in catalog.courses {
            for url in [entry.archiveURL, entry.descriptorURL] {
                try require(url.scheme == "https" && url.host == "github.com"
                            && url.path.hasPrefix("/sergii-ziborov/crabrix-courses/releases/download/")
                            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil,
                            "Unexpected course asset URL")
            }
            try require(entry.archiveBytes > 0 && entry.archiveBytes <= 80 * 1024 * 1024,
                        "Invalid course archive budget")
            for digest in [entry.archiveSHA256, entry.descriptorSHA256] {
                try require(digest.count == 64 && digest.utf8.allSatisfy({
                    (48...57).contains($0) || (97...102).contains($0)
                }), "Invalid asset digest")
            }
        }
        return catalog
    }
    let academy = try catalog("ActiveCourseCatalog/catalog.v1.json")
    try require(academy.sequence >= 15, "Academy catalog predates the verified Atlas source corpus")
    let atlas = try catalog("AtlasReplayCatalog.json")
    try require(atlas.courses.count == 20 && Set(atlas.courses.map(\.courseID)).count == 20,
                "Expected 20 independent Atlas sections")
    try require(atlas.courses.allSatisfy({
        $0.courseID.hasPrefix("atlas-") && $0.requiredCapabilities == ["atlas-replay-v1"]
            && $0.archiveBytes <= 8 * 1024 * 1024
    }), "Invalid Atlas data-pack profile")
    print("Production signatures verified: Academy catalog \(academy.sequence), Atlas catalog \(atlas.sequence), 20 optional data sections.")
} catch {
    FileHandle.standardError.write(Data("Catalog verification failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
