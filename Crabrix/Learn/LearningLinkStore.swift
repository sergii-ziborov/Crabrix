import Foundation
import Security

/// A learning link's identity: an 18-byte id and a 32-byte secret, both from
/// `SecRandomCopyBytes`. The secret never leaves the Keychain except inside
/// the personal URL the learner copies into their agent.
struct LearningLinkCredentials: Equatable, Sendable {
    /// 24 characters of base64url.
    let linkID: String
    /// 32 bytes.
    let secret: Data

    static let mcpBase = "https://crabrix.com/mcp/learn/"

    init?(linkID: String, secret: Data) {
        guard linkID.count == 24, let raw = Base64URL.decode(linkID), raw.count == LearningLinkCrypto.linkIDByteCount,
              secret.count == LearningLinkCrypto.secretByteCount else { return nil }
        self.linkID = linkID
        self.secret = secret
    }

    static func generate() throws -> LearningLinkCredentials {
        let id = Base64URL.encode(try LearningLinkCrypto.randomBytes(LearningLinkCrypto.linkIDByteCount))
        guard let credentials = LearningLinkCredentials(
            linkID: id, secret: try LearningLinkCrypto.randomBytes(LearningLinkCrypto.secretByteCount)
        ) else { throw LearningLinkCrypto.Failure.invalidSecret }
        return credentials
    }

    /// `https://crabrix.com/mcp/learn/<linkId>/<secret>`.
    var url: URL { url(mcpBase: Self.mcpBase) }

    func url(mcpBase: String) -> URL { URL(string: mcpBase + linkID + "/" + Base64URL.encode(secret))! }

    func keys() throws -> LearningLinkCrypto.Keys { try LearningLinkCrypto.keys(secret: secret) }

    /// The Keychain value: `{"linkId":"…","secret":"…"}`.
    func encoded() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["linkId": linkID, "secret": Base64URL.encode(secret)],
                                   options: [.sortedKeys])
    }

    static func decode(_ data: Data) -> LearningLinkCredentials? {
        guard data.count <= 1_024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["linkId"] as? String, let secretText = object["secret"] as? String,
              let secret = Base64URL.decode(secretText) else { return nil }
        return LearningLinkCredentials(linkID: id, secret: secret)
    }
}

/// Where the credentials live. The app uses the Keychain; tests and the
/// Debug UI stub use memory.
protocol LearningLinkSecretStore: Sendable {
    func load() throws -> LearningLinkCredentials?
    func save(_ credentials: LearningLinkCredentials) throws
    func remove() throws
}

/// One generic-password item, this device only and never synchronised, so it
/// is in no iCloud Keychain, backup or `.crabrixprogress` file.
struct LearningLinkKeychain: LearningLinkSecretStore {
    static let service = "com.sergiiziborov.Crabrix.learning-link.v1"
    let service: String
    let account = "learning-link"

    struct Failure: Error, Equatable { let status: OSStatus }

    init(service: String = Self.service) { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> LearningLinkCredentials? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let data = result as? Data else { return nil }
        return LearningLinkCredentials.decode(data)
    }

    func save(_ credentials: LearningLinkCredentials) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try credentials.encoded(),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if updated != errSecSuccess {
            throw Failure(status: updated)
        }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}

final class InMemoryLearningLinkSecrets: LearningLinkSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: LearningLinkCredentials?

    init(_ credentials: LearningLinkCredentials? = nil) { stored = credentials }

    func load() throws -> LearningLinkCredentials? { lock.withLock { stored } }
    func save(_ credentials: LearningLinkCredentials) throws { lock.withLock { stored = credentials } }
    func remove() throws { lock.withLock { stored = nil } }
}

/// A Disconnect that could not reach crabrix.com: only the link id and the
/// write token, enough to delete the encrypted copy there and nothing more
/// (no key, no read token). Retried when the app is next active or Learn
/// appears; removed once the website confirms the link is gone.
struct LearningLinkPendingDeletion: Codable, Equatable, Sendable {
    let linkID: String
    let writeToken: String
}

protocol LearningLinkPendingDeletionStore: Sendable {
    func load() -> LearningLinkPendingDeletion?
    func save(_ pending: LearningLinkPendingDeletion) throws
    func remove()
}

/// The same Keychain service as the link, another account; this device only.
struct LearningLinkPendingDeletionKeychain: LearningLinkPendingDeletionStore {
    let service: String
    let account = "pending-deletion"

    init(service: String = LearningLinkKeychain.service) { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func load() -> LearningLinkPendingDeletion? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(LearningLinkPendingDeletion.self, from: data)
    }

    func save(_ pending: LearningLinkPendingDeletion) throws {
        remove()
        var item = query
        item[kSecValueData as String] = try JSONEncoder().encode(pending)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw LearningLinkKeychain.Failure(status: status) }
    }

    func remove() { SecItemDelete(query as CFDictionary) }
}

final class InMemoryLearningLinkPendingDeletion: LearningLinkPendingDeletionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: LearningLinkPendingDeletion?

    init(_ pending: LearningLinkPendingDeletion? = nil) { stored = pending }

    func load() -> LearningLinkPendingDeletion? { lock.withLock { stored } }
    func save(_ pending: LearningLinkPendingDeletion) throws { lock.withLock { stored = pending } }
    func remove() { lock.withLock { stored = nil } }
}

/// Non-secret bookkeeping, `crabrix.ai.learningLink.v1`: when the link was
/// made and last synced, and what the website said about the agent. Neither
/// the id nor the secret is here.
struct LearningLinkLocalState: Codable, Equatable, Sendable {
    var connectedAt: Date
    var lastSyncedAt: Date?
    var lastSnapshotDigest: String?
    var lastAgentReadAt: Date?
    var serverUpdatedAt: Date?
    var pendingInbox: Int?

    static let key = "crabrix.ai.learningLink.v1"

    static func load(_ defaults: UserDefaults) -> LearningLinkLocalState? {
        guard let data = defaults.data(forKey: key), data.count <= 16 * 1_024 else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Self.self, from: data)
    }

    func save(_ defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(self) { defaults.set(data, forKey: Self.key) }
    }

    static func clear(_ defaults: UserDefaults) { defaults.removeObject(forKey: key) }
}

/// The website's learning-link API (`/api/learn-links/v1/…`). The app uses
/// only the write token; bodies are envelopes the website cannot read. Paths
/// end in `/` because the site redirects the other form, and a redirect is
/// never followed here (it could drop or leak `Authorization`).
struct LearningLinkAPI: Sendable {
    static let defaultBaseURL = URL(string: "https://crabrix.com/api/learn-links/v1/")!

    #if DEBUG
    /// Debug builds only, for an end-to-end check against a local website and
    /// MCP server: `-CrabrixLearningLinkOrigin http://127.0.0.1:3471` and
    /// `-CrabrixLearningLinkMCPOrigin http://127.0.0.1:3472`. Loopback origins
    /// only; Release builds have no override and always use crabrix.com.
    static func loopbackOrigin(_ argument: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count,
              let components = URLComponents(string: arguments[index + 1]),
              components.scheme == "http", ["127.0.0.1", "localhost"].contains(components.host ?? ""),
              components.path.isEmpty || components.path == "/", components.query == nil
        else { return nil }
        return "http://\(components.host!)" + (components.port.map { ":\($0)" } ?? "")
    }
    #endif

    enum Failure: Error, Equatable {
        case offline
        /// Unknown link or wrong token: revoked or expired.
        case notFound
        /// `CRABRIX_LEARN_LINKS=off`: 503.
        case paused
        case conflict
        /// 429, with `Retry-After` in seconds when the website sent it.
        case rateLimited(retryAfter: TimeInterval?)
        case server(Int)
        case invalidResponse
    }

    struct Status: Equatable, Sendable {
        let updatedAt: Date?
        let lastAgentReadAt: Date?
        let pendingInbox: Int
    }

    struct InboxItem: Equatable, Sendable {
        let id: String
        let createdAt: Date?
        let envelope: LearningLinkEnvelope
    }

    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = Self.defaultBaseURL, session: URLSession = Self.makeSession()) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Ephemeral like the status check: no cookies, cache or stored
    /// credentials, no redirects, 15 seconds for an upload of up to 256 KB.
    static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
        if let protocolClasses { configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? []) }
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    func create(_ credentials: LearningLinkCredentials) async throws {
        let keys = try credentials.keys()
        let body = try JSONSerialization.data(withJSONObject: [
            "linkId": credentials.linkID,
            "writeTokenSha256": keys.writeTokenSHA256,
            "readTokenSha256": keys.readTokenSHA256,
        ], options: [.sortedKeys])
        _ = try await send("POST", path: "", token: nil, body: body)
    }

    func putSnapshot(_ envelope: Data, credentials: LearningLinkCredentials) async throws {
        _ = try await send("PUT", path: "\(credentials.linkID)/snapshot/", token: credentials.keys().writeToken,
                           body: envelope)
    }

    func status(_ credentials: LearningLinkCredentials) async throws -> Status {
        let data = try await send("GET", path: "\(credentials.linkID)/status/", token: credentials.keys().writeToken)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.invalidResponse
        }
        return Status(updatedAt: Self.date(root["updatedAt"]), lastAgentReadAt: Self.date(root["lastAgentReadAt"]),
                      pendingInbox: (root["pendingInbox"] as? NSNumber)?.intValue ?? 0)
    }

    /// Oldest first, as the website returns them.
    func inbox(_ credentials: LearningLinkCredentials) async throws -> [InboxItem] {
        let data = try await send("GET", path: "\(credentials.linkID)/inbox/", token: credentials.keys().writeToken,
                                  maximumBytes: 1_024 * 1_024)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { throw Failure.invalidResponse }
        return items.prefix(50).compactMap { item in
            let rawID = (item["id"] as? String) ?? (item["id"] as? NSNumber)?.stringValue
            guard let id = rawID, Self.isMessageID(id),
                  let envelope = item["envelope"] as? [String: Any],
                  let version = envelope["v"] as? NSNumber, let nonce = envelope["nonce"] as? String,
                  let ct = envelope["ct"] as? String, ct.utf8.count <= 16 * 1_024 else { return nil }
            return InboxItem(id: id, createdAt: Self.date(item["createdAt"]),
                             envelope: LearningLinkEnvelope(v: version.intValue, nonce: nonce, ct: ct))
        }
    }

    func acknowledge(_ messageID: String, credentials: LearningLinkCredentials) async throws {
        guard Self.isMessageID(messageID) else { throw Failure.invalidResponse }
        _ = try await send("DELETE", path: "\(credentials.linkID)/inbox/\(messageID)/",
                           token: credentials.keys().writeToken)
    }

    func deleteLink(_ credentials: LearningLinkCredentials) async throws {
        try await deleteLink(linkID: credentials.linkID, writeToken: credentials.keys().writeToken)
    }

    func deleteLink(linkID: String, writeToken: String) async throws {
        guard linkID.count == 24, linkID.unicodeScalars.allSatisfy(Base64URL.isAlphabet) else { throw Failure.invalidResponse }
        _ = try await send("DELETE", path: "\(linkID)/", token: writeToken)
    }

    /// A message id becomes part of a path, so only a short URL-safe one is used.
    static func isMessageID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy(Base64URL.isAlphabet)
    }

    private func send(_ method: String, path: String, token: String?, body: Data? = nil,
                      maximumBytes: Int = 64 * 1_024) async throws -> Data {
        // `URL(string: "")` is nil: the create call goes to the base itself.
        guard let url = path.isEmpty ? baseURL : URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw Failure.invalidResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.offline
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        switch http.statusCode {
        case 200...299:
            guard data.count <= maximumBytes else { throw Failure.invalidResponse }
            return data
        case 404: throw Failure.notFound
        case 409: throw Failure.conflict
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw Failure.rateLimited(retryAfter: retry.map { min(max($0, 0), 86_400) })
        case 503: throw Failure.paused
        default: throw Failure.server(http.statusCode)
        }
    }

    /// ISO 8601 text, or seconds / milliseconds since 1970.
    static func date(_ value: Any?) -> Date? {
        if let text = value as? String { return TutorMessageValidator.parseDate(text) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let raw = number.doubleValue
            guard raw > 0 else { return nil }
            return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1_000 : raw)
        }
        return nil
    }

    /// Every answer comes from crabrix.com; a redirect is not followed.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}
