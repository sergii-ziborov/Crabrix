import XCTest
@testable import Crabrix

final class CratesIOClientTests: XCTestCase {
    func testSearchURLContainsQuerySortAndBoundedPageSize() throws {
        let url = try XCTUnwrap(
            CratesIOClient.searchURL(
                query: "serde json",
                sort: .recentDownloads,
                page: 0,
                perPage: 500
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        XCTAssertEqual(values["q"], "serde json")
        XCTAssertEqual(values["sort"], "recent-downloads")
        XCTAssertEqual(values["page"], "1")
        XCTAssertEqual(values["per_page"], "100")
    }

    func testDecodesCratesIOSearchFields() throws {
        let json = #"{"id":"serde","name":"serde","description":"framework","downloads":1234567,"recent_downloads":4321,"max_version":"1.0.219","newest_version":"1.0.219","updated_at":"2026-08-01","repository":"https://github.com/serde-rs/serde"}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let crate = try decoder.decode(CrateSearchResult.self, from: Data(json.utf8))

        XCTAssertEqual(crate.name, "serde")
        XCTAssertEqual(crate.maxVersion, "1.0.219")
        XCTAssertEqual(crate.recentDownloads, 4_321)
        XCTAssertEqual(CrateCountFormatter.compact(crate.downloads), "1.23M")
    }

    func testAllVisibleSortsMapToRegistryValues() {
        XCTAssertEqual(Set(CratesIOSort.allCases.map(\.apiValue)), [
            "relevance", "downloads", "recent-downloads", "recent-updates", "new", "alpha",
        ])
    }
}
