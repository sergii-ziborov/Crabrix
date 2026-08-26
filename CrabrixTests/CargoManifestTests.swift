import XCTest
@testable import Crabrix

final class CargoManifestTests: XCTestCase {
    func testParsesPackageAndDependencySources() throws {
        let source = """
        [package]
        name = "parser-lab"
        version = "0.2.0"
        edition = "2024" # current edition

        [dependencies]
        anyhow = "1"
        serde = { version = "1.0", features = ["derive"] }
        local-core = { path = "../local-core" }
        remote-core = { git = "https://example.com/core.git" }
        """

        let manifest = try XCTUnwrap(CargoManifest.parse(source))

        XCTAssertEqual(manifest.name, "parser-lab")
        XCTAssertEqual(manifest.version, "0.2.0")
        XCTAssertEqual(manifest.edition, "2024")
        XCTAssertEqual(manifest.dependencies.map(\.name), ["anyhow", "local-core", "remote-core", "serde"])
        XCTAssertEqual(manifest.dependencies.first(where: { $0.name == "anyhow" })?.requirement, "1")
        XCTAssertEqual(manifest.dependencies.first(where: { $0.name == "serde" })?.source, .registry)
        XCTAssertEqual(manifest.dependencies.first(where: { $0.name == "local-core" })?.source, .path)
        XCTAssertEqual(manifest.dependencies.first(where: { $0.name == "remote-core" })?.source, .git)
    }

    func testRequiresPackageName() {
        XCTAssertNil(CargoManifest.parse("[dependencies]\nanyhow = \"1\""))
    }
}
