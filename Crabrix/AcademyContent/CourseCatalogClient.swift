import Foundation

private struct AcceptedCourseCatalog: Codable {
    let sequence: Int
    let envelopeBase64: String
    let versionDigests: [String: String]
}

/// A network catalog can add versions, but cannot replace an accepted version
/// digest or roll the sequence backwards. The last signed catalog survives a
/// network outage; installed packs are stored independently from this file.
actor CourseCatalogClient {
    static let publicCatalogURL = URL(
        string: "https://raw.githubusercontent.com/sergii-ziborov/crabrix-courses/main/catalog.v1.json"
    )!

    private let stateURL: URL
    private let keyring: CourseKeyring
    private let session: URLSession
    private let trustedHosts: Set<String>

    init(stateURL: URL, keyring: CourseKeyring,
         trustedHosts: Set<String> = ["raw.githubusercontent.com"]) {
        self.stateURL = stateURL
        self.keyring = keyring
        self.trustedHosts = trustedHosts
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.httpMaximumConnectionsPerHost = 2
        session = URLSession(
            configuration: configuration,
            delegate: CourseDeliveryHostGuard(hosts: trustedHosts),
            delegateQueue: nil
        )
    }

    func current() throws -> CourseCatalogPayload? {
        guard let state = try readState() else { return nil }
        guard let bytes = Data(base64Encoded: state.envelopeBase64) else {
            throw CoursePackError.invalidCatalog
        }
        let catalog = try CoursePackVerifier.catalog(
            bytes: bytes, keyring: keyring, lastAcceptedSequence: state.sequence - 1
        )
        guard catalog.sequence == state.sequence,
              Self.digests(in: catalog).allSatisfy({ state.versionDigests[$0.key] == $0.value }) else {
            throw CoursePackError.invalidCatalog
        }
        return catalog
    }

    func refresh(from url: URL = publicCatalogURL) async throws -> CourseCatalogPayload {
        try requireTrusted(url)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              bytes.count <= 1_000_000 else { throw CoursePackError.invalidCatalog }
        let old = try readState()
        if let old,
           let acceptedBytes = Data(base64Encoded: old.envelopeBase64),
           acceptedBytes == bytes,
           let current = try current() {
            return current
        }
        let catalog = try CoursePackVerifier.catalog(
            bytes: bytes, keyring: keyring,
            lastAcceptedSequence: old?.sequence ?? 0,
            acceptedVersions: old?.versionDigests ?? [:]
        )
        var digests = old?.versionDigests ?? [:]
        digests.merge(Self.digests(in: catalog)) { _, new in new }
        let accepted = AcceptedCourseCatalog(
            sequence: catalog.sequence,
            envelopeBase64: bytes.base64EncodedString(),
            versionDigests: digests
        )
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(accepted).write(to: stateURL, options: .atomic)
        return catalog
    }

    private func readState() throws -> AcceptedCourseCatalog? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        return try JSONDecoder().decode(AcceptedCourseCatalog.self, from: Data(contentsOf: stateURL))
    }

    private func requireTrusted(_ url: URL) throws {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              trustedHosts.contains(host), url.user == nil, url.password == nil else {
            throw CoursePackError.invalidCatalog
        }
    }

    private static func digests(in catalog: CourseCatalogPayload) -> [String: String] {
        Dictionary(uniqueKeysWithValues: catalog.courses.map {
            ("\($0.courseID)|\($0.language)|\($0.contentVersion)", $0.archiveSHA256)
        })
    }
}

/// Applied to every redirect as well as the initial URL check. Asset delivery
/// can use a separate instance with the two documented GitHub release hosts.
final class CourseDeliveryHostGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let hosts: Set<String>

    init(hosts: Set<String>) { self.hosts = hosts }

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
}
