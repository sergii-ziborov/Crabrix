import Foundation
import XCTest
@testable import Crabrix

final class CoursePackVerifierTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        // XcodeGen flattens resource folders in the generated test bundle.
        // Keep the nested lookup for projects that preserve the directory.
        return try XCTUnwrap(
            bundle.url(forResource: name, withExtension: nil, subdirectory: "CoursePack")
                ?? bundle.url(forResource: name, withExtension: nil)
        )
    }

    private func keyring() throws -> CourseKeyring {
        try JSONDecoder().decode(CourseKeyring.self, from: Data(contentsOf: fixture("production-keyring.json")))
    }

    func testPublishedCourseArchiveAndCatalog() throws {
        let keys = try keyring()
        let catalogBytes = try Data(contentsOf: fixture("catalog.v1.json"))
        let catalog = try CoursePackVerifier.catalog(bytes: catalogBytes, keyring: keys, lastAcceptedSequence: 1)
        XCTAssertEqual(catalog.sequence, 2)
        XCTAssertEqual(catalog.courses.count, 7)

        let descriptorBytes = try Data(contentsOf: fixture("basics.descriptor.json"))
        let course = try CoursePackVerifier.verify(
            descriptorBytes: descriptorBytes,
            archiveURL: fixture("basics-1.0.1.zip"),
            keyring: keys
        )
        XCTAssertEqual(course.descriptor.courseID, "basics")
        XCTAssertEqual(course.descriptor.contentVersion, "1.0.1")
        XCTAssertFalse(course.manifest.files.isEmpty)
    }

    func testTamperedArchiveAndCatalogRollbackFailClosed() throws {
        let keys = try keyring()
        let catalogBytes = try Data(contentsOf: fixture("catalog.v1.json"))
        XCTAssertThrowsError(try CoursePackVerifier.catalog(
            bytes: catalogBytes, keyring: keys, lastAcceptedSequence: 2
        ))

        let original = try Data(contentsOf: fixture("basics-1.0.1.zip"))
        var changed = original
        changed[changed.count - 1] ^= 1
        let work = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = work.appending(path: "basics-1.0.1.zip")
        try changed.write(to: archive)
        XCTAssertThrowsError(try CoursePackVerifier.verify(
            descriptorBytes: Data(contentsOf: fixture("basics.descriptor.json")),
            archiveURL: archive,
            keyring: keys
        ))
    }

    func testCrossLanguageDomainSeparatedSignatureVector() throws {
        struct Vectors: Decodable {
            struct Case: Decodable { let domainPrefixUTF8: String; let signatureBase64: String }
            let cases: [String: Case]
            let keyID: String
            let payloadBase64: String
            let publicKeyBase64: String
        }
        let vector = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: fixture("signature-vectors.json")))
        let keyring = CourseKeyring(keys: [vector.keyID: vector.publicKeyBase64])
        for (kind, sample) in vector.cases {
            let envelope = CourseEnvelope(
                keyID: vector.keyID,
                payloadBase64: vector.payloadBase64,
                signatureBase64: sample.signatureBase64
            )
            let bytes = try JSONEncoder().encode(envelope)
            let domain = Data(sample.domainPrefixUTF8.utf8)
            let payload = try CoursePackVerifier.signedPayload(bytes, domain: domain, keyring: keyring).0
            XCTAssertEqual(payload, Data(base64Encoded: vector.payloadBase64), kind)
            let wrong = kind == "catalog" ? CoursePackVerifier.descriptorDomain : CoursePackVerifier.catalogDomain
            XCTAssertThrowsError(try CoursePackVerifier.signedPayload(bytes, domain: wrong, keyring: keyring))
        }
    }
}
