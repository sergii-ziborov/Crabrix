import CryptoKit
import Foundation
import XCTest
@testable import Crabrix

private final class CourseDownloadURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Data] = [:]
    nonisolated(unsafe) private static var requests: [String: Int] = [:]
    nonisolated(unsafe) private static var interruptOnce: Set<String> = []
    nonisolated(unsafe) private static var invalidRangeOnce: Set<String> = []
    nonisolated(unsafe) private static var ignoreRangeOnce: Set<String> = []
    nonisolated(unsafe) private static var rangeRequests: [String: [String]] = [:]

    static func supply(_ data: Data, at url: URL) {
        lock.withLock { responses[url.absoluteString] = data }
    }

    static func count(for url: URL) -> Int {
        lock.withLock { requests[url.absoluteString] ?? 0 }
    }

    static func interruptFirstTransfer(at url: URL) {
        lock.withLock { _ = interruptOnce.insert(url.absoluteString) }
    }

    static func ranges(for url: URL) -> [String] {
        lock.withLock { rangeRequests[url.absoluteString] ?? [] }
    }

    static func invalidateNextRange(at url: URL) {
        lock.withLock { _ = invalidRangeOnce.insert(url.absoluteString) }
    }

    static func ignoreNextRange(at url: URL) {
        lock.withLock { _ = ignoreRangeOnce.insert(url.absoluteString) }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "github.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let range = request.value(forHTTPHeaderField: "Range")
        let (body, interrupted, invalidRange, ignoreRange) = Self.lock.withLock {
            () -> (Data?, Bool, Bool, Bool) in
            Self.requests[url.absoluteString, default: 0] += 1
            if let range {
                Self.rangeRequests[url.absoluteString, default: []].append(range)
            }
            let interrupted = range == nil && Self.interruptOnce.remove(url.absoluteString) != nil
            let invalidRange = range != nil
                && Self.invalidRangeOnce.remove(url.absoluteString) != nil
            let ignoreRange = range != nil
                && Self.ignoreRangeOnce.remove(url.absoluteString) != nil
            return (Self.responses[url.absoluteString], interrupted, invalidRange, ignoreRange)
        }
        var payload = body
        var headers: [String: String] = [
            "ETag": "\"course-archive-v1\"", "Accept-Ranges": "bytes"
        ]
        var status = body == nil ? 404 : 200
        if let range, let body, !ignoreRange,
           range.hasPrefix("bytes="), range.hasSuffix("-"),
           let start = Int(range.dropFirst(6).dropLast()), start < body.count {
            status = 206
            payload = body.subdata(in: start..<body.count)
            headers["Content-Range"] = "bytes \(start)-\(body.count - 1)/\(invalidRange ? body.count + 1 : body.count)"
        }
        if let payload { headers["Content-Length"] = String(payload.count) }
        let response = HTTPURLResponse(
            url: url, statusCode: status,
            httpVersion: nil, headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if interrupted, let payload {
            client?.urlProtocol(self, didLoad: payload.prefix(70_000))
            // Give AsyncBytes time to deliver the first chunk before the mock
            // connection fails; an immediate fail can discard buffered bytes.
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) {
                self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
            return
        }
        if let payload { client?.urlProtocol(self, didLoad: payload) }
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

    func testLegacyResumeBlobIsDiscardedBeforeVerifiedFreshDownload() async throws {
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

    func testInterruptedArchiveResumesFromPersistedBytesAfterManagerRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = try Data(contentsOf: fixture("basics.descriptor.json"))
        let archive = try Data(contentsOf: fixture("basics-1.0.1.zip"))
        let entry = entry(descriptor: descriptor, archive: archive, root: UUID().uuidString)
        CourseDownloadURLProtocol.interruptFirstTransfer(at: entry.archiveURL)
        let firstManager = try CourseDownloadManager(cacheRoot: root, session: session())

        do {
            _ = try await firstManager.download(entry)
            XCTFail("An interrupted transfer was accepted")
        } catch {
            let partial = root.appending(path: "\(entry.archiveSHA256).partial")
            let bytes = try XCTUnwrap(partial.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            XCTAssertGreaterThan(bytes, 0)
            XCTAssertLessThan(bytes, archive.count)

            let relaunchedManager = try CourseDownloadManager(cacheRoot: root, session: session())
            let downloaded = try await relaunchedManager.download(entry)
            XCTAssertEqual(try Data(contentsOf: downloaded.archive), archive)
            XCTAssertEqual(CourseDownloadURLProtocol.ranges(for: entry.archiveURL), ["bytes=\(bytes)-"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: root.appending(path: "\(entry.archiveSHA256).transfer.json").path
            ))
        }
    }

    func testRangeIgnoredReplacesPartialWithFullSignedArchive() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = try Data(contentsOf: fixture("basics.descriptor.json"))
        let archive = try Data(contentsOf: fixture("basics-1.0.1.zip"))
        let entry = entry(descriptor: descriptor, archive: archive, root: UUID().uuidString)
        try Data(archive.prefix(70_000)).write(
            to: root.appending(path: "\(entry.archiveSHA256).partial")
        )
        let transfer: [String: Any] = [
            "archiveSHA256": entry.archiveSHA256,
            "archiveBytes": entry.archiveBytes,
            "strongETag": NSNull()
        ]
        try JSONSerialization.data(withJSONObject: transfer).write(
            to: root.appending(path: "\(entry.archiveSHA256).transfer.json"), options: .atomic
        )
        CourseDownloadURLProtocol.ignoreNextRange(at: entry.archiveURL)
        let manager = try CourseDownloadManager(cacheRoot: root, session: session())

        let downloaded = try await manager.download(entry)

        XCTAssertEqual(try Data(contentsOf: downloaded.archive), archive)
        XCTAssertEqual(CourseDownloadURLProtocol.ranges(for: entry.archiveURL), ["bytes=70000-"])
    }

    func testMismatchedContentRangeCannotActivatePartialArchive() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = try Data(contentsOf: fixture("basics.descriptor.json"))
        let archive = try Data(contentsOf: fixture("basics-1.0.1.zip"))
        let entry = entry(descriptor: descriptor, archive: archive, root: UUID().uuidString)
        let partial = root.appending(path: "\(entry.archiveSHA256).partial")
        try Data(archive.prefix(70_000)).write(to: partial)
        let transfer: [String: Any] = [
            "archiveSHA256": entry.archiveSHA256,
            "archiveBytes": entry.archiveBytes,
            "strongETag": NSNull()
        ]
        try JSONSerialization.data(withJSONObject: transfer).write(
            to: root.appending(path: "\(entry.archiveSHA256).transfer.json"), options: .atomic
        )
        CourseDownloadURLProtocol.invalidateNextRange(at: entry.archiveURL)
        let manager = try CourseDownloadManager(cacheRoot: root, session: session())

        do {
            _ = try await manager.download(entry)
            XCTFail("A mismatched Content-Range was accepted")
        } catch CoursePackError.archiveDigestMismatch {
            XCTAssertEqual(CourseDownloadURLProtocol.ranges(for: entry.archiveURL), ["bytes=70000-"])
            XCTAssertEqual(try Data(contentsOf: partial), Data(archive.prefix(70_000)))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: root.appending(path: "\(entry.archiveSHA256).zip").path
            ))
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
