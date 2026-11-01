import Foundation
import ZIPFoundation

actor GitHubProjectImporter {
    enum ImportError: LocalizedError {
        case invalidResponse
        case temporarilyUnavailable(Int)
        case downloadTooLarge
        case archiveTooLarge
        case unsafeArchivePath(String)
        case repositoryHasNoCargoProject

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "GitHub did not return a repository archive. Check the URL or repository visibility."
            case let .temporarilyUnavailable(status):
                "GitHub is busy or rate limiting requests (HTTP \(status)). Try again shortly."
            case .downloadTooLarge:
                "The GitHub snapshot exceeds the 40 MB download limit."
            case .archiveTooLarge:
                "The expanded GitHub snapshot exceeds the safe import limit."
            case let .unsafeArchivePath(path):
                "The archive contains an unsafe path: \(path)"
            case .repositoryHasNoCargoProject:
                "No Cargo, Rust, HTML or package.json source was found in this repository."
            }
        }
    }

    private let maximumDownloadBytes: Int64 = 40_000_000
    private let maximumArchiveBytes: UInt64 = 100_000_000
    private let maximumArchiveEntries = 4_000
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// A failure a later attempt could fix, as opposed to a link that will never import.
    static func isTransient(_ error: Error) -> Bool {
        if case ImportError.temporarilyUnavailable = error { return true }
        return error is URLError
    }

    /// GitHub answers rate limiting with 429, or with 403 and one of these headers.
    /// A plain 403 means the repository cannot be read, like a 404.
    private static func failure(for response: HTTPURLResponse) -> ImportError? {
        switch response.statusCode {
        case 200..<300: return nil
        case 408, 429, 500..<600: return .temporarilyUnavailable(response.statusCode)
        case 403 where response.value(forHTTPHeaderField: "Retry-After") != nil
            || response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0":
            return .temporarilyUnavailable(response.statusCode)
        default: return .invalidResponse
        }
    }

    func importProject(from rawURL: String) async throws -> CrabrixProject {
        let reference = try GitHubRepositoryReference.parse(rawURL)
        let request = URLRequest(
            url: reference.archiveURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 60
        )
        let (downloadedURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw ImportError.invalidResponse }
        if let failure = Self.failure(for: httpResponse) { throw failure }
        if response.expectedContentLength > maximumDownloadBytes {
            throw ImportError.downloadTooLarge
        }

        let fileManager = FileManager.default
        let workURL = fileManager.temporaryDirectory
            .appending(path: "CrabrixGitHub-\(UUID().uuidString)", directoryHint: .isDirectory)
        let archiveURL = workURL.appending(path: "repository.zip")
        let extractionURL = workURL.appending(path: "extracted", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: workURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workURL) }
        try fileManager.moveItem(at: downloadedURL, to: archiveURL)

        let archiveSize = try archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard Int64(archiveSize) <= maximumDownloadBytes else { throw ImportError.downloadTooLarge }
        try validateArchive(at: archiveURL)
        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        try CrabrixProjectArchive.expand(archiveURL, to: extractionURL, maximumBytes: maximumArchiveBytes) {
            ImportError.archiveTooLarge
        }

        let provenance = CrabrixProject.Provenance(
            source: .github,
            owner: reference.owner,
            repository: reference.repository,
            reference: reference.reference ?? "HEAD",
            commit: nil,
            importedAt: Date()
        )
        do {
            return try LocalProjectLoader.load(from: extractionURL, provenance: provenance)
        } catch LocalProjectLoader.ProjectError.noReadableSource {
            throw ImportError.repositoryHasNoCargoProject
        }
    }

    private func validateArchive(at url: URL) throws {
        let archive = try Archive(url: url, accessMode: .read)
        var totalBytes: UInt64 = 0
        var entryCount = 0
        for entry in archive {
            entryCount += 1
            guard entryCount <= maximumArchiveEntries else { throw ImportError.archiveTooLarge }
            totalBytes += UInt64(entry.uncompressedSize)
            guard totalBytes <= maximumArchiveBytes else { throw ImportError.archiveTooLarge }

            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.hasPrefix("/"),
                  !components.contains(".."),
                  entry.type != .symlink
            else {
                throw ImportError.unsafeArchivePath(entry.path)
            }
        }
    }
}
