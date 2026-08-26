import Foundation

enum CratesIOSort: String, CaseIterable, Identifiable, Sendable {
    case relevance
    case downloads
    case recentDownloads
    case recentUpdates
    case newest
    case name

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .relevance: "relevance"
        case .downloads: "downloads"
        case .recentDownloads: "recent-downloads"
        case .recentUpdates: "recent-updates"
        case .newest: "new"
        case .name: "alpha"
        }
    }

    var title: String {
        switch self {
        case .relevance: "Relevance"
        case .downloads: "Most downloaded"
        case .recentDownloads: "Trending"
        case .recentUpdates: "Recently updated"
        case .newest: "Newest"
        case .name: "Name"
        }
    }

    var systemImage: String {
        switch self {
        case .relevance: "sparkles"
        case .downloads: "arrow.down.circle.fill"
        case .recentDownloads: "chart.line.uptrend.xyaxis"
        case .recentUpdates: "clock.arrow.circlepath"
        case .newest: "calendar.badge.plus"
        case .name: "textformat.abc"
        }
    }
}

struct CrateSearchResult: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String?
    let downloads: Int
    let recentDownloads: Int?
    let maxVersion: String
    let newestVersion: String?
    let updatedAt: String?
    let repository: String?
}

struct CrateSearchPage: Sendable {
    let crates: [CrateSearchResult]
    let total: Int
}

struct CrateOwner: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let login: String
    let name: String?

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? login : trimmed
    }
}

struct CrateVersion: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let num: String
    let downloads: Int
    let yanked: Bool
    let rustVersion: String?
    let createdAt: String?
}

struct CratePackageDetails: Sendable {
    let versions: [CrateVersion]
    let owners: [CrateOwner]
}

enum CratesIOError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "Could not create the crates.io request."
        case .invalidResponse: "crates.io returned an unreadable response."
        case let .server(code): "crates.io returned HTTP \(code)."
        }
    }
}

actor CratesIOClient {
    static let shared = CratesIOClient()

    private struct SearchResponse: Decodable {
        struct Meta: Decodable { let total: Int }
        let crates: [CrateSearchResult]
        let meta: Meta
    }

    private struct OwnersResponse: Decodable { let users: [CrateOwner] }
    private struct PackageResponse: Decodable { let versions: [CrateVersion] }

    private let session: URLSession
    private var ownerCache: [String: [CrateOwner]] = [:]
    private var packageCache: [String: CratePackageDetails] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(
        query: String,
        sort: CratesIOSort,
        page: Int = 1,
        perPage: Int = 30
    ) async throws -> CrateSearchPage {
        guard let url = Self.searchURL(
            query: query,
            sort: sort,
            page: page,
            perPage: perPage
        ) else {
            throw CratesIOError.invalidRequest
        }
        let response: SearchResponse = try await get(url)
        return CrateSearchPage(crates: response.crates, total: response.meta.total)
    }

    func owners(for crate: String) async throws -> [CrateOwner] {
        if let cached = ownerCache[crate] { return cached }
        guard let encoded = crate.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://crates.io/api/v1/crates/\(encoded)/owners") else {
            throw CratesIOError.invalidRequest
        }
        let response: OwnersResponse = try await get(url)
        ownerCache[crate] = response.users
        return response.users
    }

    func package(named crate: String) async throws -> CratePackageDetails {
        if let cached = packageCache[crate] { return cached }
        guard let encoded = crate.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://crates.io/api/v1/crates/\(encoded)") else {
            throw CratesIOError.invalidRequest
        }

        async let packageRequest: PackageResponse = get(url)
        async let ownersRequest = try? owners(for: crate)
        let response = try await packageRequest
        let resolvedOwners = await ownersRequest ?? []
        let details = CratePackageDetails(
            versions: response.versions,
            owners: resolvedOwners
        )
        packageCache[crate] = details
        return details
    }

    nonisolated static func searchURL(
        query: String,
        sort: CratesIOSort,
        page: Int,
        perPage: Int
    ) -> URL? {
        var components = URLComponents(string: "https://crates.io/api/v1/crates")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "sort", value: sort.apiValue),
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "per_page", value: String(min(max(perPage, 1), 100))),
        ]
        return components?.url
    }

    private func get<Response: Decodable & Sendable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Crabrix/0.1 (https://github.com/sergii-ziborov/Crabrix)",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CratesIOError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CratesIOError.server(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data)
    }
}

enum CrateCountFormatter {
    static func compact(_ value: Int) -> String {
        let amount = Double(value)
        switch amount {
        case 1_000_000_000...:
            return formatted(amount / 1_000_000_000, suffix: "B")
        case 1_000_000...:
            return formatted(amount / 1_000_000, suffix: "M")
        case 1_000...:
            return formatted(amount / 1_000, suffix: "K")
        default:
            return String(value)
        }
    }

    static func exact(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private static func formatted(_ value: Double, suffix: String) -> String {
        let digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        return value.formatted(
            .number.precision(.fractionLength(0...digits))
        ) + suffix
    }
}

@MainActor
final class CrateCatalogViewModel: ObservableObject {
    @Published var query = ""
    @Published var sort: CratesIOSort = .downloads
    @Published private(set) var results: [CrateSearchResult] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let client: CratesIOClient
    private var searchTask: Task<Void, Never>?

    init(client: CratesIOClient = .shared) {
        self.client = client
    }

    func start() async {
        guard results.isEmpty else { return }
        await performSearch()
    }

    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await self?.performSearch()
            } catch {
                return
            }
        }
    }

    func retry() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in await self?.performSearch() }
    }

    private func performSearch() async {
        isLoading = true
        errorMessage = nil
        do {
            let page = try await client.search(
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                sort: sort
            )
            guard !Task.isCancelled else { return }
            results = page.crates
            total = page.total
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

@MainActor
final class CratePackageViewModel: ObservableObject {
    @Published private(set) var versions: [CrateVersion] = []
    @Published private(set) var owners: [CrateOwner] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var selectedVersion: String?

    let crate: CrateSearchResult
    private let client: CratesIOClient

    init(crate: CrateSearchResult, client: CratesIOClient = .shared) {
        self.crate = crate
        self.client = client
        selectedVersion = crate.maxVersion
    }

    func load() async {
        guard versions.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let package = try await client.package(named: crate.name)
            owners = package.owners
            versions = package.versions.sorted { lhs, rhs in
                lhs.createdAt ?? "" > rhs.createdAt ?? ""
            }
            if let current = versions.first(where: { !$0.yanked && $0.num == crate.maxVersion }) {
                selectedVersion = current.num
            } else {
                selectedVersion = versions.first(where: { !$0.yanked })?.num
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
