import CryptoKit
import Foundation

/// Fetches signed course assets into a purgeable cache. Only CourseInstaller
/// can activate them after descriptor, ZIP and manifest verification.
actor CourseDownloadManager {
    private static let hosts: Set<String> = [
        "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"
    ]
    private let cacheRoot: URL
    private let session: URLSession

    init(cacheRoot: URL? = nil, session: URLSession? = nil) throws {
        if let cacheRoot {
            self.cacheRoot = cacheRoot
        } else {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            else { throw CoursePackError.invalidCatalog }
            self.cacheRoot = caches.appending(path: "Crabrix/CourseDownloads", directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(at: self.cacheRoot, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 15 * 60
        configuration.httpMaximumConnectionsPerHost = 2
        self.session = session ?? URLSession(configuration: configuration)
    }

    func download(_ entry: CourseCatalogPayload.Entry,
                  progress: (@Sendable (Int, Int) -> Void)? = nil) async throws
        -> (descriptor: Data, archive: URL) {
        try Self.requireTrusted(entry.descriptorURL)
        try Self.requireTrusted(entry.archiveURL)
        guard entry.archiveBytes > 0,
              entry.archiveBytes <= CoursePackVerifier.maximumArchiveBytes else {
            throw CoursePackError.sizeLimit
        }
        _ = try Self.component(entry.courseID)
        _ = try Self.component(entry.language)
        _ = try Self.component(entry.contentVersion)
        guard Self.isDigest(entry.archiveSHA256), Self.isDigest(entry.descriptorSHA256) else {
            throw CoursePackError.invalidCatalog
        }
        // A resume record belongs to exact signed bytes, not just a mutable
        // course name/version pair.
        let resumeURL = cacheRoot.appending(path: "\(entry.archiveSHA256).resume")
        let archiveURL = cacheRoot.appending(path: "\(entry.archiveSHA256).zip")

        let descriptorGuard = CourseAssetTransferGuard(hosts: Self.hosts, maximumBytes: 1_000_000)
        let (descriptorStream, descriptorResponse) = try await session.bytes(
            for: URLRequest(url: entry.descriptorURL), delegate: descriptorGuard
        )
        guard (descriptorResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw CoursePackError.archiveDigestMismatch
        }
        var descriptor = Data()
        for try await byte in descriptorStream {
            guard descriptor.count < 1_000_000 else { throw CoursePackError.sizeLimit }
            descriptor.append(byte)
        }
        guard Self.hex(SHA256.hash(data: descriptor)) == entry.descriptorSHA256 else {
            throw CoursePackError.archiveDigestMismatch
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: archiveURL.path),
           (attributes[.size] as? NSNumber)?.intValue == entry.archiveBytes,
           let digest = try? Self.hashFile(archiveURL), digest == entry.archiveSHA256 {
            return (descriptor, archiveURL)
        }

        let guarder = CourseAssetTransferGuard(
            hosts: Self.hosts, maximumBytes: entry.archiveBytes, progress: progress
        )
        let resumeData: Data?
        if let bytes = try? resumeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           bytes > 0, bytes <= 1_000_000 {
            resumeData = try? Data(contentsOf: resumeURL)
        } else {
            resumeData = nil
            try? FileManager.default.removeItem(at: resumeURL)
        }
        do {
            let (temporary, response): (URL, URLResponse)
            if let resumeData {
                do {
                    (temporary, response) = try await session.download(
                        resumeFrom: resumeData, delegate: guarder
                    )
                } catch {
                    if !Task.isCancelled, !guarder.exceeded {
                        // Opaque URLSession resume data may become unusable after
                        // relaunch or cache eviction. One clean retry restores
                        // the normal Download action instead of trapping Resume.
                        try? FileManager.default.removeItem(at: resumeURL)
                        try await Task.sleep(for: .milliseconds(300))
                        (temporary, response) = try await session.download(
                            for: URLRequest(url: entry.archiveURL), delegate: guarder
                        )
                    } else {
                        throw error
                    }
                }
            } else {
                (temporary, response) = try await session.download(
                    for: URLRequest(url: entry.archiveURL), delegate: guarder
                )
            }
            guard Self.ok(response), !guarder.exceeded,
                  (try temporary.resourceValues(forKeys: [.fileSizeKey])).fileSize == entry.archiveBytes,
                  try Self.hashFile(temporary) == entry.archiveSHA256 else {
                throw CoursePackError.archiveDigestMismatch
            }
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                try FileManager.default.removeItem(at: archiveURL)
            }
            try FileManager.default.moveItem(at: temporary, to: archiveURL)
            try? FileManager.default.removeItem(at: resumeURL)
            return (descriptor, archiveURL)
        } catch {
            if let bytes = Self.resumeBytes(from: error) {
                try? bytes.write(to: resumeURL, options: .atomic)
            }
            throw guarder.exceeded ? CoursePackError.sizeLimit : error
        }
    }

    private static func ok(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200 || http.statusCode == 206
    }

    private static func requireTrusted(_ url: URL) throws {
        guard url.scheme == "https", let host = url.host?.lowercased(), hosts.contains(host),
              url.user == nil, url.password == nil else { throw CoursePackError.invalidCatalog }
    }

    private static func component(_ value: String) throws -> String {
        let checked = try CoursePackVerifier.validatedPath(value)
        guard !checked.contains("/"), !checked.isEmpty else {
            throw CoursePackError.unsafeArchive(value)
        }
        return checked
    }

    private static func isDigest(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private static func resumeBytes(from error: Error) -> Data? {
        guard let bytes = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
              !bytes.isEmpty, bytes.count <= 1_000_000 else { return nil }
        return bytes
    }

    private static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

private final class CourseAssetTransferGuard: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let hosts: Set<String>
    private let maximumBytes: Int
    private let progress: (@Sendable (Int, Int) -> Void)?
    private let lock = NSLock()
    private var limitExceeded = false

    init(hosts: Set<String>, maximumBytes: Int,
         progress: (@Sendable (Int, Int) -> Void)? = nil) {
        self.hosts = hosts
        self.maximumBytes = maximumBytes
        self.progress = progress
    }

    var exceeded: Bool { lock.withLock { limitExceeded } }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https",
              let host = url.host?.lowercased(), hosts.contains(host),
              url.user == nil, url.password == nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumBytes {
            lock.withLock { limitExceeded = true }
            downloadTask.cancel()
        } else {
            progress?(Int(totalBytesWritten), maximumBytes)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
