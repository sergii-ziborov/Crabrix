import CryptoKit
import Foundation
import XCTest
@testable import Crabrix

private final class CourseDownloadURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Data] = [:]
    nonisolated(unsafe) private static var requests: [String: Int] = [:]

    static func supply(_ data: Data, at url: URL) {
        lock.withLock { responses[url.absoluteString] = data }
    }

    static func count(for url: URL) -> Int {
        lock.withLock { requests[url.absoluteString] ?? 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "github.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = Self.lock.withLock { () -> Data? in
            Self.requests[url.absoluteString, default: 0] += 1
            return Self.responses[url.absoluteString]
        }
        let response = HTTPURLResponse(
            url: url, statusCode: body == nil ? 404 : 200,
            httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class CourseDownloadManagerTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        let packs = try XCTUnwrap(Bundle.main.url(
            forResource: "MigrationCoursePacks", withExtension: nil
        ))
        return packs.appending(path: name)
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CourseDownloadURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func entry(descriptor: Data, archive: Data, root: String) -> CourseCatalogPayload.Entry {
        let descriptorURL = URL(string: "https://github.com/\(root)/descriptor")!
        let archiveURL = URL(string: "https://github.com/\(root)/archive")!
        CourseDownloadURLProtocol.supply(descriptor, at: descriptorURL)
        CourseDownloadURLProtocol.supply(archive, at: archiveURL)
        return CourseCatalogPayload.Entry(
            courseID: "basics", language: "en", contentVersion: "1.0.1",
            descriptorURL: descriptorURL, descriptorSHA256: Self.sha256(descriptor),
            archiveURL: archiveURL, archiveSHA256: Self.sha256(archive),
            archiveBytes: archive.count, minimumAppVersion: "1.1", requiredCapabilities: []
        )
    }

    func testCorruptResumeRecordFallsBackToVerifiedFreshDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = try Data(contentsOf: fixture("basics.descriptor.json"))
        let archive = try Data(contentsOf: fixture("basics-1.0.1.zip"))
        let entry = entry(descriptor: descriptor, archive: archive, root: UUID().uuidString)
        let resumeURL = root.appending(path: "\(entry.archiveSHA256).resume")
        try Data("invalid resume".utf8).write(to: resumeURL)
        let manager = try CourseDownloadManager(cacheRoot: root, session: session())

        let downloaded = try await manager.download(entry)

        XCTAssertEqual(downloaded.descriptor, descriptor)
        XCTAssertEqual(try Data(contentsOf: downloaded.archive), archive)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resumeURL.path))
        XCTAssertEqual(CourseDownloadURLProtocol.count(for: entry.archiveURL), 1)
    }

    func testDescriptorStopsAtAcceptedByteLimitBeforeArchiveFetch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = Data(repeating: 0x41, count: 1_000_001)
        let archive = try Data(contentsOf: fixture("basics-1.0.1.zip"))
        let entry = entry(descriptor: descriptor, archive: archive, root: UUID().uuidString)
        let manager = try CourseDownloadManager(cacheRoot: root, session: session())

        do {
            _ = try await manager.download(entry)
            XCTFail("An oversized descriptor was accepted")
        } catch CoursePackError.sizeLimit {
            XCTAssertEqual(CourseDownloadURLProtocol.count(for: entry.archiveURL), 0)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
