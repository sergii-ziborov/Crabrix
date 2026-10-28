import Foundation
import Security
import CrabrixGit

/// One credential per canonical repository URL, never in a project, defaults,
/// Git config or Shared data. Device-only items are deliberately not synced.
actor GitCredentialVault {
    private let service: String
    private struct Secret: Codable { let username: String; let token: String }

    init(service: String = "com.sergiiziborov.Crabrix.git-https.v1") { self.service = service }

    func save(url: String, username: String, token: String) throws {
        _ = try GitHTTPSCredential(username: username, token: token)
        let query = try query(url)
        let data = try JSONEncoder().encode(Secret(username: username, token: token))
        guard data.count <= 32_768 else { throw GitRepositoryFailure("The encoded HTTPS credential exceeds the Keychain profile.") }
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            try check(SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil))
        } else { try check(updated) }
    }

    func load(url: String) throws -> GitHTTPSCredential? {
        guard let secret = try read(url) else { return nil }
        return try GitHTTPSCredential(username: secret.username, token: secret.token)
    }

    func username(url: String) throws -> String? { try read(url)?.username }

    func remove(url: String) throws {
        let status = SecItemDelete(try query(url) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func read(_ url: String) throws -> Secret? {
        var request = try query(url)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, data.count <= 32_768 else {
            throw GitRepositoryFailure("The saved HTTPS credential could not be read from Keychain.")
        }
        return try JSONDecoder().decode(Secret.self, from: data)
    }

    private func query(_ url: String) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: try GitHTTPSAddress.canonical(url),
         kSecAttrSynchronizable as String: false]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw GitRepositoryFailure("Keychain could not complete the HTTPS credential operation (\(status)).")
        }
    }
}
