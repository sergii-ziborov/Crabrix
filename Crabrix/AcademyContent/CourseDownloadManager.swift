import CryptoKit
import Foundation

private struct CoursePartialTransfer: Codable {
    let archiveSHA256: String
    let archiveBytes: Int
    let strongETag: String?
}

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
        // Partial bytes belong to the exact digest and expected length, never
        // merely to a mutable course name or content version.
        let partialURL = cacheRoot.appending(path: "\(entry.archiveSHA256).partial")
        let transferURL = cacheRoot.appending(path: "\(entry.archiveSHA256).transfer.json")
        let archiveURL = cacheRoot.appending(path: "\(entry.archiveSHA256).zip")

        let descriptorGuard = CourseAssetRedirectGuard(hosts: Self.hosts)
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
        if let bytes = try? Self.fileSize(at: archiveURL),
           bytes == entry.archiveBytes,
           let digest = try? Self.hashFile(archiveURL), digest == entry.archiveSHA256 {
            Self.resetPartial(partialURL: partialURL, transferURL: transferURL)
            return (descriptor, archiveURL)
        }

        // Old URLSession resume blobs are not a reliable process-kill record.
        // The new transport keeps accepted bytes in our own purgeable cache.
        try? FileManager.default.removeItem(at: cacheRoot.appending(
            path: "\(entry.archiveSHA256).resume"
        ))
        try await fetchArchive(
            entry, partialURL: partialURL, transferURL: transferURL,
            archiveURL: archiveURL, progress: progress
        )
        return (descriptor, archiveURL)
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

    private func fetchArchive(
        _ entry: CourseCatalogPayload.Entry,
        partialURL: URL,
        transferURL: URL,
        archiveURL: URL,
        progress: (@Sendable (Int, Int) -> Void)?
    ) async throws {
        var (offset, savedETag) = Self.validatedPartial(
            entry, partialURL: partialURL, transferURL: transferURL
        )
        if offset == entry.archiveBytes {
            if try Self.finishPartial(entry, partialURL: partialURL,
                                      transferURL: transferURL, archiveURL: archiveURL) {
                progress?(offset, entry.archiveBytes)
                return
            }
            Self.resetPartial(partialURL: partialURL, transferURL: transferURL)
            offset = 0
            savedETag = nil
        }

        if offset > 0 {
            if try await resumeArchive(
                entry, from: offset, savedETag: savedETag, partialURL: partialURL,
                transferURL: transferURL, archiveURL: archiveURL, progress: progress
            ) {
                return
            }
            // A 416 response means the host rejected the saved range. Make
            // one fresh request using the exact signed asset URL.
            Self.resetPartial(partialURL: partialURL, transferURL: transferURL)
            offset = 0
            savedETag = nil
        }

        try Task.checkCancellation()
        let guarder = CourseAssetRedirectGuard(hosts: Self.hosts)
        let (stream, response) = try await session.bytes(
            for: URLRequest(url: entry.archiveURL), delegate: guarder
        )
        guard let http = response as? HTTPURLResponse else {
            throw CoursePackError.archiveDigestMismatch
        }
        switch http.statusCode {
        case 200: break
        case 206:
            guard Self.validContentRange(http.value(forHTTPHeaderField: "Content-Range"),
                                         start: 0, total: entry.archiveBytes) else {
                throw CoursePackError.archiveDigestMismatch
            }
        default:
            throw CoursePackError.archiveDigestMismatch
        }
        let transfer = CoursePartialTransfer(
            archiveSHA256: entry.archiveSHA256, archiveBytes: entry.archiveBytes,
            strongETag: Self.strongETag(http)
        )
        try JSONEncoder().encode(transfer).write(to: transferURL, options: .atomic)
        try await Self.append(
            stream, to: partialURL, from: 0, maximumBytes: entry.archiveBytes,
            progress: progress
        )
        guard try Self.fileSize(at: partialURL) == entry.archiveBytes else {
            // A short transfer remains resumable even if the server ended
            // the response without reporting a network error.
            throw CoursePackError.archiveDigestMismatch
        }
        guard try Self.finishPartial(
            entry, partialURL: partialURL, transferURL: transferURL, archiveURL: archiveURL
        ) else {
            Self.resetPartial(partialURL: partialURL, transferURL: transferURL)
            throw CoursePackError.archiveDigestMismatch
        }
    }

    /// URLSession's file download API delivers a bounded temporary suffix for
    /// a Range response. If it is interrupted, our earlier partial stays on
    /// disk; the next launch can request the same missing suffix again.
    private func resumeArchive(
        _ entry: CourseCatalogPayload.Entry,
        from offset: Int,
        savedETag: String?,
        partialURL: URL,
        transferURL: URL,
        archiveURL: URL,
        progress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> Bool {
        var request = URLRequest(url: entry.archiveURL)
        request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        if let savedETag { request.setValue(savedETag, forHTTPHeaderField: "If-Range") }
        let guarder = CourseAssetRedirectGuard(
            hosts: Self.hosts, maximumBytes: entry.archiveBytes,
            startingBytes: offset, progress: progress
        )
        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await session.download(for: request, delegate: guarder)
        } catch {
            throw guarder.exceeded ? CoursePackError.sizeLimit : error
        }
        guard !guarder.exceeded else { throw CoursePackError.sizeLimit }
        guard let http = response as? HTTPURLResponse else {
            throw CoursePackError.archiveDigestMismatch
        }
        if http.statusCode == 416 { return false }
        let suffixInfo = try temporary.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard suffixInfo.isRegularFile == true, suffixInfo.isSymbolicLink != true,
              let suffixBytes = suffixInfo.fileSize else {
            throw CoursePackError.archiveDigestMismatch
        }
        let writeOffset: Int
        switch http.statusCode {
        case 200:
            // A host may ignore Range or reject If-Range. Its full response
            // replaces the old partial, never appends to it.
            Self.resetPartial(partialURL: partialURL, transferURL: transferURL)
            writeOffset = 0
        case 206:
            guard Self.validContentRange(
                http.value(forHTTPHeaderField: "Content-Range"), start: offset,
                total: entry.archiveBytes, receivedBytes: suffixBytes
            ) else { throw CoursePackError.archiveDigestMismatch }
            if let savedETag, let returnedETag = Self.strongETag(http),
               returnedETag != savedETag {
                Self.resetPartial(partialURL: partialURL, transferURL: transferURL)
                throw CoursePackError.archiveDigestMismatch
            }
            writeOffset = offset
        default:
            throw CoursePackError.archiveDigestMismatch
        }
        let transfer = CoursePartialTransfer(
            archiveSHA256: entry.archiveSHA256, archiveBytes: entry.archiveBytes,
            strongETag: Self.strongETag(http) ?? (writeOffset > 0 ? savedETag : nil)
        )
        try JSONEncoder().encode(transfer).write(to: transferURL, options: .atomic)
        try Self.appendFile(
            temporary, to: partialURL, from: writeOffset,
            maximumBytes: entry.archiveBytes, progress: progress
        )
        guard try Self.fileSize(at: partialURL) == entry.archiveBytes else {
            throw CoursePackError.archiveDigestMismatch
        }
        guard try Self.finishPartial(
            entry, partialURL: partialURL, transferURL: transferURL, archiveURL: archiveURL
        ) else {
            Self.resetPartial(partialURL: partialURL, transferURL: transferURL)
            throw CoursePackError.archiveDigestMismatch
        }
        return true
    }

    private static func appendFile(
        _ source: URL, to partialURL: URL, from offset: Int,
        maximumBytes: Int, progress: (@Sendable (Int, Int) -> Void)?
    ) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        if !FileManager.default.fileExists(atPath: partialURL.path) {
            guard FileManager.default.createFile(atPath: partialURL.path, contents: nil) else {
                throw CoursePackError.archiveDigestMismatch
            }
        }
        let output = try FileHandle(forWritingTo: partialURL)
        defer { try? output.close() }
        guard try output.seekToEnd() == UInt64(offset) else {
            throw CoursePackError.archiveDigestMismatch
        }
        var accepted = offset
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            guard chunk.count <= maximumBytes - accepted else { throw CoursePackError.sizeLimit }
            try output.write(contentsOf: chunk)
            accepted += chunk.count
            progress?(accepted, maximumBytes)
        }
        try output.synchronize()
    }

    private static func validatedPartial(
        _ entry: CourseCatalogPayload.Entry, partialURL: URL, transferURL: URL
    ) -> (Int, String?) {
        let fm = FileManager.default
        guard let partial = try? partialURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        ), partial.isRegularFile == true, partial.isSymbolicLink != true,
              let bytes = try? fileSize(at: partialURL), bytes > 0, bytes <= entry.archiveBytes,
              let transferInfo = try? transferURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
              ), transferInfo.isRegularFile == true, transferInfo.isSymbolicLink != true,
              let transferSize = transferInfo.fileSize, transferSize > 0, transferSize <= 4_096,
              let data = try? Data(contentsOf: transferURL),
              let transfer = try? JSONDecoder().decode(CoursePartialTransfer.self, from: data),
              transfer.archiveSHA256 == entry.archiveSHA256,
              transfer.archiveBytes == entry.archiveBytes,
              transfer.strongETag.map(isStrongETag) ?? true else {
            if fm.fileExists(atPath: partialURL.path) || fm.fileExists(atPath: transferURL.path) {
                resetPartial(partialURL: partialURL, transferURL: transferURL)
            }
            return (0, nil)
        }
        return (bytes, transfer.strongETag)
    }

    private static func resetPartial(partialURL: URL, transferURL: URL) {
        try? FileManager.default.removeItem(at: partialURL)
        try? FileManager.default.removeItem(at: transferURL)
    }

    private static func finishPartial(
        _ entry: CourseCatalogPayload.Entry,
        partialURL: URL, transferURL: URL, archiveURL: URL
    ) throws -> Bool {
        guard try fileSize(at: partialURL) == entry.archiveBytes,
              try hashFile(partialURL) == entry.archiveSHA256 else { return false }
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
        }
        try FileManager.default.moveItem(at: partialURL, to: archiveURL)
        try? FileManager.default.removeItem(at: transferURL)
        return true
    }

    private static func append(
        _ stream: URLSession.AsyncBytes, to partialURL: URL,
        from offset: Int, maximumBytes: Int,
        progress: (@Sendable (Int, Int) -> Void)?
    ) async throws {
        if !FileManager.default.fileExists(atPath: partialURL.path) {
            guard FileManager.default.createFile(atPath: partialURL.path, contents: nil) else {
                throw CoursePackError.archiveDigestMismatch
            }
        }
        let output = try FileHandle(forWritingTo: partialURL)
        guard try output.seekToEnd() == UInt64(offset) else {
            try? output.close()
            throw CoursePackError.archiveDigestMismatch
        }
        var accepted = offset
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        do {
            for try await byte in stream {
                guard accepted < maximumBytes else { throw CoursePackError.sizeLimit }
                buffer.append(byte)
                accepted += 1
                if buffer.count == 64 * 1024 {
                    try Task.checkCancellation()
                    try output.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                    progress?(accepted, maximumBytes)
                }
            }
            try Task.checkCancellation()
            if !buffer.isEmpty {
                try output.write(contentsOf: buffer)
                progress?(accepted, maximumBytes)
            }
            try output.synchronize()
            try output.close()
        } catch {
            // Flush the last accepted bytes so a process restart can request
            // precisely the missing range. The final SHA-256 still decides
            // whether any partial transfer becomes an installed archive.
            if !buffer.isEmpty { try? output.write(contentsOf: buffer) }
            try? output.synchronize()
            try? output.close()
            throw error
        }
    }

    private static func validContentRange(
        _ value: String?, start: Int, total: Int, receivedBytes: Int? = nil
    ) -> Bool {
        guard let value else { return false }
        let parts = value.split(separator: " ")
        guard parts.count == 2, parts[0] == "bytes" else { return false }
        let rangeAndTotal = parts[1].split(separator: "/")
        guard rangeAndTotal.count == 2, Int(rangeAndTotal[1]) == total else { return false }
        let bounds = rangeAndTotal[0].split(separator: "-")
        guard bounds.count == 2, Int(bounds[0]) == start,
              let end = Int(bounds[1]), end >= start, end < total else { return false }
        if let receivedBytes, receivedBytes != end - start + 1 { return false }
        return true
    }

    private static func strongETag(_ response: HTTPURLResponse) -> String? {
        guard let etag = response.value(forHTTPHeaderField: "ETag"),
              isStrongETag(etag) else { return nil }
        return etag
    }

    private static func isStrongETag(_ etag: String) -> Bool {
        !etag.isEmpty && !etag.hasPrefix("W/") && etag.utf8.count <= 200
            && !etag.contains("\r") && !etag.contains("\n")
    }

    private static func isDigest(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    /// URL.resourceValues can return a cached file size from before an append.
    /// The archive must be checked against fresh filesystem metadata.
    private static func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let bytes = attributes[.size] as? NSNumber else {
            throw CoursePackError.archiveDigestMismatch
        }
        return bytes.intValue
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

private final class CourseAssetRedirectGuard: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let hosts: Set<String>
    private let maximumBytes: Int?
    private let startingBytes: Int
    private let progress: (@Sendable (Int, Int) -> Void)?
    private let lock = NSLock()
    private var limitExceeded = false

    init(hosts: Set<String>, maximumBytes: Int? = nil, startingBytes: Int = 0,
         progress: (@Sendable (Int, Int) -> Void)? = nil) {
        self.hosts = hosts
        self.maximumBytes = maximumBytes
        self.startingBytes = startingBytes
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
        guard let maximumBytes else { return }
        if totalBytesWritten > maximumBytes {
            lock.withLock { limitExceeded = true }
            downloadTask.cancel()
        } else {
            progress?(min(maximumBytes, startingBytes + Int(totalBytesWritten)), maximumBytes)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
