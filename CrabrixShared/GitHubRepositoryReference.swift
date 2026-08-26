import Foundation

struct GitHubRepositoryReference: Codable, Equatable, Sendable {
    enum ParseError: LocalizedError, Equatable {
        case invalidURL
        case unsupportedHost
        case missingRepository

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "Enter a complete GitHub repository URL."
            case .unsupportedHost:
                "Only github.com repository links are supported."
            case .missingRepository:
                "The GitHub URL must contain an owner and repository."
            }
        }
    }

    let owner: String
    let repository: String
    let reference: String?

    var canonicalURL: URL {
        URL(string: "https://github.com/\(owner)/\(repository)")!
    }

    var archiveURL: URL {
        let requestedReference = reference ?? "HEAD"
        let encodedReference = requestedReference
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "https://github.com/\(owner)/\(repository)/archive/\(encodedReference).zip")!
    }

    static func parse(_ rawValue: String) throws -> GitHubRepositoryReference {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let host = components.host?.lowercased()
        else {
            throw ParseError.invalidURL
        }
        guard host == "github.com" || host == "www.github.com" else {
            throw ParseError.unsupportedHost
        }

        let segments = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard segments.count >= 2 else { throw ParseError.missingRepository }

        let owner = segments[0]
        let repository = segments[1].hasSuffix(".git")
            ? String(segments[1].dropLast(4))
            : segments[1]
        guard !owner.isEmpty, !repository.isEmpty else { throw ParseError.missingRepository }

        let reference: String?
        if segments.count >= 4, segments[2] == "tree" {
            reference = segments.dropFirst(3).joined(separator: "/")
        } else {
            reference = nil
        }

        return GitHubRepositoryReference(
            owner: owner,
            repository: repository,
            reference: reference?.isEmpty == false ? reference : nil
        )
    }
}
