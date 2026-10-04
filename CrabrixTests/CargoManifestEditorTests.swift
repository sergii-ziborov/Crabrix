import XCTest
@testable import Crabrix

final class CargoManifestEditorTests: XCTestCase {
    func testSynParserProfileRepairsPlainDependencyWithoutChangingOtherEntries() throws {
        let source = """
        [package]
        name = "weather-station"
        version = "0.1.0"
        edition = "2024"
        [dependencies]
        syn = "3.0.6"
        log = "0.4" # keep this comment
        """
        let updated = try CargoManifestEditor.usingSynParserFeatures(source)
        let manifest = try CratePackageManifest.parse(updated)
        let syn = try XCTUnwrap(manifest.dependencies.first { $0.alias == "syn" })
        XCTAssertFalse(syn.usesDefaultFeatures)
        XCTAssertEqual(Set(syn.features), Set(["derive", "parsing", "printing", "clone-impls"]))
        XCTAssertTrue(updated.contains("log = \"0.4\" # keep this comment"))
        XCTAssertEqual(try CargoManifestEditor.usingSynParserFeatures(updated), updated)
    }

    func testRemovalPreservesOtherDependenciesAndTheirFormatting() throws {
        let source = """
        # My project 🦀
        [package]
        name = "removal"
        version = "0.1.0"

        [dependencies]
        "maps" = { package = "hashbrown", version = "0.17.1" } # renamed
        log = "0.4" # keep this comment
        [dev-dependencies]
        maps = "1"
        """
        let updated = try CargoManifestEditor.removingDependency("maps", from: source)
        let document = try TOMLParser.parse(updated)
        XCTAssertNil(document["dependencies"]?["maps"])
        XCTAssertEqual(document["dev-dependencies"]?["maps"]?.stringValue, "1")
        XCTAssertTrue(updated.contains("log = \"0.4\" # keep this comment"))
        XCTAssertTrue(updated.hasPrefix("# My project 🦀\n[package]"))
        XCTAssertEqual(CargoManifest.parse(updated)?.dependencies.map(\.name), ["log"])
    }

    func testTableAndTargetDependenciesAreRemovedWithTheirFeatureReferences() throws {
        let source = """
        [package]
        name = "table-removal"
        [dependencies.maps]
        package = "hashbrown"
        version = "0.17.1"
        optional = true
        features = [
            "default-hasher",
        ]
        [target.'cfg(unix)'.dependencies.'maps'] # same alias
        package = "hashbrown"
        version = "0.17.1"
        [dependencies.log]
        version = "0.4"
        [features]
        default = ["maps", "dep:maps", "maps/serde", "maps?/rayon", "log/std"]
        another = []
        """
        XCTAssertEqual(CargoManifest.parse(source)?.dependencies.map(\.name), ["log", "maps"])
        let updated = try CargoManifestEditor.removingDependency("maps", from: source)
        let manifest = try CratePackageManifest.parse(updated)
        XCTAssertEqual(manifest.dependencies.map(\.alias), ["log"])
        XCTAssertEqual(manifest.features["default"], ["log/std"])
        XCTAssertEqual(manifest.features["another"], [])
    }

    func testRemovingOptionalDependencyPreservesExplicitFeatureOfTheSameName() throws {
        let source = """
        [package]
        name = "explicit-feature"
        [dependencies]
        maps = { version = "1", optional = true }
        [features]
        default = ["maps"]
        maps = ["dep:maps"]
        """
        let updated = try CargoManifestEditor.removingDependency("maps", from: source)
        let manifest = try CratePackageManifest.parse(updated)
        XCTAssertTrue(manifest.dependencies.isEmpty)
        XCTAssertEqual(manifest.features["default"], ["maps"])
        XCTAssertEqual(manifest.features["maps"], [])
    }

    func testDottedDependencyKeysAreRemovedAndUnknownAliasLeavesDocumentUntouched() throws {
        let source = """
        [package]
        name = "dotted"
        [dependencies]
        maps.package = "hashbrown"
        maps.version = "0.17.1"
        log = "0.4"
        """
        XCTAssertEqual(try CargoManifestEditor.removingDependency("missing", from: source), source)
        let updated = try CargoManifestEditor.removingDependency("maps", from: source)
        XCTAssertEqual(CargoManifest.parse(updated)?.dependencies.map(\.name), ["log"])
    }
}
