import Foundation
import Security
import SwiftUI

/// Publishes the rating to the public board at crabrix.com.
///
/// There is no account. A player is a random key generated once and kept in the
/// Keychain, plus whatever display name they type. Nothing else leaves the
/// device: no email, no password, no identifier tied to the person or the phone.
/// Publishing is opt-in and can be turned off, which stops any further sends.
@MainActor
final class LeaderboardClient: ObservableObject {
    enum Status: Equatable {
        case idle
        case sending
        case published(rank: Int?, total: Int?)
        /// The entry was deleted from the board at the reader's request.
        case removed
        case failed(String)
    }

    struct Entry: Identifiable, Decodable, Equatable {
        let rank: Int
        let name: String
        let title: String
        let points: Int
        let lessons: Int
        let linesChanged: Int
        let achievements: Int
        let bestRecall: Int

        var id: Int { rank }
    }

    private struct BoardResponse: Decodable { let entries: [Entry] }
    private struct SubmitResponse: Decodable {
        let rank: Int?
        let total: Int?
    }

    static var boardURL: URL { CrabrixLinks.leaderboard }
    /// Where a reader reports an offensive name, as guideline 1.2 requires.
    static var supportURL: URL { CrabrixLinks.support }
    private static let apiRoot = URL(string: "https://crabrix.com/api")!

    // Plain @Published backed by UserDefaults rather than @AppStorage: the
    // toggle and the name field bind through this object, and @AppStorage
    // inside a class does not announce its changes to a view.
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    @Published var displayName: String {
        didSet { defaults.set(displayName, forKey: Self.nameKey) }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var board: [Entry] = []

    private let session: URLSession
    private let defaults: UserDefaults
    private var lastPublishedPoints: Int?
    private static let enabledKey = "crabrix.leaderboard.enabled"
    private static let nameKey = "crabrix.leaderboard.name"

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        displayName = defaults.string(forKey: Self.nameKey) ?? ""
    }

    /// The opaque per-device key. Created once, then read back from the Keychain.
    var playerKey: String { DeviceKey.shared.value }

    var canPublish: Bool {
        isEnabled && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Sends the current rating, if publishing is on and something changed.
    func publish(state: CrabrixProgressState, force: Bool = false) async {
        guard canPublish else { return }
        guard force || lastPublishedPoints != state.totalPoints else { return }
        guard state.totalPoints > 0 else { return }

        status = .sending
        var request = URLRequest(url: Self.apiRoot.appendingPathComponent("score"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "key": playerKey,
            "name": displayName.trimmingCharacters(in: .whitespaces),
            "rankTitle": CrabrixRank.rank(for: state.totalPoints).title,
            "points": state.totalPoints,
            "lessons": state.lessonsCompleted,
            "linesChanged": state.linesChanged,
            "achievements": state.unlockedAchievementIDs.count,
            "bestRecall": state.codeRecallBestLevel,
        ])

        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                status = .failed(
                    code == 400
                        ? "That display name is not allowed on the public board. Try another."
                        : "The board rejected that submission."
                )
                return
            }
            let decoded = try JSONDecoder().decode(SubmitResponse.self, from: data)
            lastPublishedPoints = state.totalPoints
            status = .published(rank: decoded.rank, total: decoded.total)
        } catch {
            // Publishing is a bonus, never a requirement: local rating is the
            // source of truth and the next attempt will carry the same numbers.
            status = .failed("Could not reach the board. Your rating is safe on this device.")
        }
    }

    /// Loads the public top of the board, for the in-app preview.
    func loadBoard(limit: Int = 25) async {
        var components = URLComponents(
            url: Self.apiRoot.appendingPathComponent("leaderboard"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components?.url else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            board = try JSONDecoder().decode(BoardResponse.self, from: data).entries
        } catch {
            // Leave whatever was already loaded rather than blanking the list.
        }
    }

    /// Turns publishing off and deletes the row from the board.
    ///
    /// App Store guideline 5.1.1(v): anything the app creates on a server has to
    /// be removable from inside the app. There is no account to close here, so
    /// the key alone is the whole request.
    @discardableResult
    func stopPublishingAndForget() async -> Bool {
        isEnabled = false
        lastPublishedPoints = nil

        var request = URLRequest(url: Self.apiRoot.appendingPathComponent("forget"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["key": playerKey])

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                status = .failed("Could not remove the entry. Try again when you are online.")
                return false
            }
            status = .removed
            board.removeAll { $0.name == displayName }
            return true
        } catch {
            status = .failed("Could not reach the board. Nothing was removed yet.")
            return false
        }
    }
}

/// A random per-install key in the Keychain.
///
/// Deliberately not the identifierForVendor or anything else derived from the
/// device: it identifies a row on a scoreboard and nothing about a person.
struct DeviceKey {
    static let shared = DeviceKey()

    private static let account = "com.sergiiziborov.Crabrix.leaderboard.key"

    var value: String {
        if let existing = Self.read() { return existing }
        let fresh = Self.generate()
        Self.write(fresh)
        return fresh
    }

    /// 32 URL-safe characters, which is what the server's key format accepts.
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty
        else { return nil }
        return text
    }

    private static func write(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            // Never leaves this device, and is not needed before first unlock.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
