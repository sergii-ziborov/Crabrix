import Foundation

/// The key and capability stay in the fragment, which is never sent in HTTP.
struct PlaygroundLink: Equatable, Sendable {
    let id: String
    let key: String
    let access: String
    let expiresAt: Date
    let isReadOnly: Bool

    static func parse(_ raw: String) throws -> PlaygroundLink {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw LinkError.invalid }
        let path: String
        if url.scheme == "https", url.host == "crabrix.com", url.user == nil, url.password == nil, url.port == nil {
            path = url.path
        } else if url.scheme == "crabrix", url.host == "playground" { path = "/playground" + url.path }
        else { throw LinkError.invalid }
        let parts = path.split(separator: "/")
        guard parts.count == 3, parts[0] == "playground", parts[1] == "room", valid(String(parts[2]), count: 24), let fragment = url.fragment,
              let parameters = URLComponents(string: "https://crabrix.com/?" + fragment)?.queryItems else { throw LinkError.invalid }
        func value(_ name: String) -> String? { parameters.first { $0.name == name }?.value }
        guard let key = value("key"), valid(key, count: 43), let access = value("access"), valid(access, count: 43),
              let time = value("expires").flatMap(Double.init), time.isFinite, time > 0, time <= 9_007_199_254_740_991, time.rounded() == time else { throw LinkError.invalid }
        return PlaygroundLink(id: String(parts[2]), key: key, access: access, expiresAt: Date(timeIntervalSince1970: time / 1000), isReadOnly: value("mode") == "view")
    }
    var url: URL {
        var parts = URLComponents(string: "https://crabrix.com/playground/room/\(id)/")!
        var fragment = URLComponents()
        fragment.queryItems = [URLQueryItem(name: "key", value: key), URLQueryItem(name: "access", value: access), URLQueryItem(name: "expires", value: String(Int64(expiresAt.timeIntervalSince1970 * 1000))), URLQueryItem(name: "mode", value: isReadOnly ? "view" : "edit")]
        parts.percentEncodedFragment = fragment.percentEncodedQuery
        return parts.url!
    }
    private static func valid(_ value: String, count: Int) -> Bool {
        value.count == count && value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }
    enum LinkError: LocalizedError { case invalid
        var errorDescription: String? { "Open a complete Crabrix Playground link, including its encryption key after #." }
    }
}
