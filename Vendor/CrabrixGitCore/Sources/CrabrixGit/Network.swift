import Foundation
@preconcurrency import CLibgit2

/// No credential can be encoded into a project or a repository URL.
public struct GitHTTPSCredential: Sendable, CustomDebugStringConvertible, CustomStringConvertible {
    let username: String
    let token: String
    public init(username: String, token: String) throws {
        guard !username.isEmpty, !token.isEmpty, username.utf8.count <= 256, token.utf8.count <= 16_384,
              !username.contains(":"), !(username + token).unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw GitRepositoryFailure("Enter a bounded single-line HTTPS username and access token.")
        }
        self.username = username; self.token = token
    }
    public var debugDescription: String { "GitHTTPSCredential(<redacted>)" }
    public var description: String { debugDescription }
}

public struct GitRemoteState: Sendable {
    public let url: String
    public let branch: String
    public let ahead: Int?
    public let behind: Int?
}

public enum GitHTTPSAddress {
    public static func canonical(_ raw: String) throws -> String {
        guard raw.utf8.count <= 1024, let value = URLComponents(string: raw), value.scheme == "https",
              let host = value.host, host == "github.com",
              value.port == nil || value.port == 443, value.user == nil, value.password == nil,
              value.query == nil, value.fragment == nil, value.path == value.percentEncodedPath else {
            throw GitRepositoryFailure("Use a direct HTTPS repository URL on github.com, without credentials, query or fragment.")
        }
        let parts = value.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        let clean = parts.last == "" ? parts.dropLast() : parts[...]
        guard clean.count == 2, clean.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 200 && $0.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) }) }) else {
            throw GitRepositoryFailure("Use a repository URL, not a branch, file, sign-in or archive URL.")
        }
        guard clean.last != ".git", !clean.contains("-") else { throw GitRepositoryFailure("Unsupported repository URL.") }
        let path = clean.joined(separator: "/")
        return "https://" + host + "/" + path + (path.hasSuffix(".git") ? "" : ".git")
    }
}

/// Lives only for one synchronous libgit2 request. Callbacks never print remote
/// sideband text or trust a remote certificate callback in place of system TLS.
final class GitNetworkContext: @unchecked Sendable {
    let address: String
    let credential: GitHTTPSCredential?
    let deadline = Date().addingTimeInterval(120)
    private let lock = NSRecursiveLock()
    private var cancelled = false
    private var attempts = 0
    private var failureValue: String?
    private var rejectedValue = false
    var failure: String? { lock.withLock { failureValue } }
    var pushRejected: Bool { lock.withLock { rejectedValue } }
    func cancel() { lock.withLock { cancelled = true } }
    func rejectPush() { lock.withLock { rejectedValue = true } }
    func acquire(_ output: UnsafeMutablePointer<UnsafeMutablePointer<git_credential>?>, url: String, allowed: UInt32) -> Int32 {
        lock.withLock {
            if proceed() < 0 { return GIT_EUSER.rawValue }
            guard let credential, attempts < 2, allowed & UInt32(GIT_CREDENTIAL_USERPASS_PLAINTEXT.rawValue) != 0,
                  url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == address else {
                failureValue = "HTTPS authentication failed or is outside the saved credential scope. Local history was kept."
                return GIT_EAUTH.rawValue
            }
            attempts += 1
            return git_credential_userpass_plaintext_new(output, credential.username, credential.token)
        }
    }
    init(_ address: String, _ credential: GitHTTPSCredential?) {
        self.address = address; self.credential = credential
    }
    func proceed(bytes: Int = 0, objects: Int = 0) -> Int32 {
        lock.withLock {
            if cancelled || Task.isCancelled { failureValue = "cancelled"; return GIT_EUSER.rawValue }
            if Date() > deadline || bytes > 128 * 1024 * 1024 || objects > 100_000 {
                failureValue = "Git transfer exceeded its two-minute / 128 MiB / 100,000-object profile. Existing local work was kept."
                return GIT_EUSER.rawValue
            }
            return 0
        }
    }

    var callbacks: git_remote_callbacks {
        var value = git_remote_callbacks()
        git_remote_init_callbacks(&value, UInt32(GIT_REMOTE_CALLBACKS_VERSION))
        value.payload = Unmanaged.passUnretained(self).toOpaque()
        value.credentials = { output, url, _, allowed, payload in
            guard let payload, let output, let url else { return GIT_EAUTH.rawValue }
            let context = Unmanaged<GitNetworkContext>.fromOpaque(payload).takeUnretainedValue()
            return context.acquire(output, url: String(cString: url), allowed: allowed)
        }
        value.transfer_progress = { stats, payload in
            guard let stats, let payload else { return GIT_EUSER.rawValue }
            return Unmanaged<GitNetworkContext>.fromOpaque(payload).takeUnretainedValue()
                .proceed(bytes: stats.pointee.received_bytes, objects: Int(stats.pointee.total_objects))
        }
        value.sideband_progress = { _, _, payload in
            guard let payload else { return GIT_EUSER.rawValue }
            return Unmanaged<GitNetworkContext>.fromOpaque(payload).takeUnretainedValue().proceed()
        }
        value.push_transfer_progress = { _, total, bytes, payload in
            guard let payload else { return GIT_EUSER.rawValue }
            return Unmanaged<GitNetworkContext>.fromOpaque(payload).takeUnretainedValue().proceed(bytes: bytes, objects: Int(total))
        }
        value.push_update_reference = { _, status, payload in
            guard let payload else { return GIT_EUSER.rawValue }
            let context = Unmanaged<GitNetworkContext>.fromOpaque(payload).takeUnretainedValue()
            if status != nil { context.rejectPush() }
            return context.proceed()
        }
        return value
    }
}
