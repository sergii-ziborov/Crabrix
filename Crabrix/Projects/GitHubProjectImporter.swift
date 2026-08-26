import Foundation
import ZIPFoundation

actor GitHubProjectImporter {
    enum ImportError: LocalizedError {
        case invalidResponse
        case downloadTooLarge
        case archiveTooLarge
        case unsafeArchivePath(String)
        case repositoryHasNoCargoProject

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "GitHub did not return a repository archive. Check the URL or repository visibility."
            case .downloadTooLarge:
                "The GitHub snapshot exceeds the 40 MB download limit."
            case .archiveTooLarge:
                "The expanded GitHub snapshot exceeds the safe import limit."
            case let .unsafeArchivePath(path):
                "The archive contains an unsafe path: \(path)"
            case .repositoryHasNoCargoProject:
                "No Cargo.toml or Rust source was found in this repository."
            }
        }
    }

    private let maximumDownloadBytes: Int64 = 40_000_000
    private let maximumArchiveBytes: UInt64 = 100_000_000
    private let maximumArchiveEntries = 4_000

    func importProject(from rawURL: String) async throws -> CrabrixProject {
        let reference = try GitHubRepositoryReference.parse(rawURL)
        let request = URLRequest(
            url: reference.archiveURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 60
        )
        let (downloadedURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw ImportError.invalidResponse
        }
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
        try fileManager.unzipItem(at: archiveURL, to: extractionURL)

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
