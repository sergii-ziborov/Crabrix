import XCTest
@testable import Crabrix

final class CratePackageManifestTests: XCTestCase {
    func testReadsPackageLibraryAndFeatureTables() throws {
        let manifest = try CratePackageManifest.parse("""
        [package]
        name = "my-crate"
        version = "1.2.3"
        edition = "2021"
        rust-version = "1.63"
        build = "build.rs"

        [lib]
        name = "my_lib"
        path = "src/other.rs"

        [features]
        default = ["std"]
        std = ["alloc"]
        alloc = []
        """)

        XCTAssertEqual(manifest.packageName, "my-crate")
        XCTAssertEqual(manifest.version?.description, "1.2.3")
        XCTAssertEqual(manifest.edition, "2021")
        XCTAssertEqual(manifest.rustVersion, "1.63")
        XCTAssertEqual(manifest.buildScriptPath, "build.rs")
        XCTAssertEqual(manifest.library.path, "src/other.rs")
        XCTAssertEqual(manifest.libraryCrateName, "my_lib")
        XCTAssertEqual(manifest.features["default"], ["std"])
    }

    func testDefaultsEditionAndDerivesCrateNameFromPackageName() throws {
        let manifest = try CratePackageManifest.parse("""
        [package]
        name = "cfg-if"
        version = "1.0.0"
        """)

        XCTAssertEqual(manifest.edition, "2015")
        XCTAssertEqual(manifest.libraryCrateName, "cfg_if")
        XCTAssertNil(manifest.buildScriptPath)
        XCTAssertFalse(manifest.isProcMacro)
    }

    func testDetectsProcMacroAndUnsupportedCrateTypes() throws {
        let procMacro = try CratePackageManifest.parse("""
        [package]
        name = "derive-thing"
        version = "1.0.0"

        [lib]
        proc-macro = true
        """)
        XCTAssertTrue(procMacro.isProcMacro)

        let cdylib = try CratePackageManifest.parse("""
        [package]
        name = "native-thing"
        version = "1.0.0"

        [lib]
        crate-type = ["cdylib", "staticlib"]
        """)
        XCTAssertTrue(cdylib.requiresUnsupportedCrateType)

        let both = try CratePackageManifest.parse("""
        [package]
        name = "dual"
        version = "1.0.0"

        [lib]
        crate-type = ["cdylib", "rlib"]
        """)
        XCTAssertFalse(both.requiresUnsupportedCrateType)
    }

    func testSeparatesDependencyKindsAndTargetPredicates() throws {
        let manifest = try CratePackageManifest.parse("""
        [package]
        name = "mixed"
        version = "1.0.0"

        [dependencies]
        anyhow = "1"
        renamed = { version = "2", package = "real-name", default-features = false }
        maybe = { version = "1", optional = true }

        [dev-dependencies]
        testkit = "1"

        [build-dependencies]
        autocfg = "1"

        [target.'cfg(windows)'.dependencies]
        winapi = "0.3"

        [target.'cfg(target_os = "wasi")'.dependencies]
        wasi = "0.11"
        """)

        let wasm = manifest.registryDependencies(for: .wasm32WasiP1)
        let names = Set(wasm.map(\.alias))
        XCTAssertTrue(names.contains("anyhow"))
        XCTAssertTrue(names.contains("wasi"))
        XCTAssertFalse(names.contains("winapi"), "Windows-only dependency must not apply")
        XCTAssertFalse(names.contains("testkit"))
        XCTAssertFalse(names.contains("autocfg"))

        let renamed = try XCTUnwrap(wasm.first { $0.alias == "renamed" })
        XCTAssertEqual(renamed.packageName, "real-name")
        XCTAssertFalse(renamed.usesDefaultFeatures)
        XCTAssertTrue(try XCTUnwrap(wasm.first { $0.alias == "maybe" }).isOptional)
    }

    func testRecognisesAVirtualWorkspaceRoot() throws {
        let manifest = try CratePackageManifest.parse("""
        [workspace]
        members = ["crates/*"]
        """)
        XCTAssertTrue(manifest.isVirtualWorkspace)
        XCTAssertTrue(manifest.packageName.isEmpty)
    }
}

final class TargetCfgExpressionTests: XCTestCase {
    private let target = RustTargetSpec.wasm32WasiP1

    func testMatchesKeyValuePredicates() {
        XCTAssertTrue(TargetCfgExpression.parse("cfg(target_os = \"wasi\")").matches(target))
        XCTAssertTrue(TargetCfgExpression.parse("cfg(target_arch = \"wasm32\")").matches(target))
        XCTAssertTrue(TargetCfgExpression.parse("cfg(target_family = \"wasm\")").matches(target))
        XCTAssertFalse(TargetCfgExpression.parse("cfg(target_os = \"linux\")").matches(target))
    }

    func testMatchesBooleanCombinators() {
        XCTAssertTrue(TargetCfgExpression.parse("cfg(not(windows))").matches(target))
        XCTAssertFalse(TargetCfgExpression.parse("cfg(unix)").matches(target))
        XCTAssertTrue(
            TargetCfgExpression.parse("cfg(any(target_os = \"wasi\", windows))").matches(target)
        )
        XCTAssertFalse(
            TargetCfgExpression.parse("cfg(all(target_os = \"wasi\", unix))").matches(target)
        )
        XCTAssertTrue(
            TargetCfgExpression
                .parse("cfg(all(target_arch = \"wasm32\", not(target_os = \"emscripten\")))")
                .matches(target)
        )
    }

    func testMatchesLiteralTriples() {
        XCTAssertTrue(TargetCfgExpression.parse("wasm32-wasip1").matches(target))
        XCTAssertTrue(TargetCfgExpression.parse("wasm32-wasi").matches(target))
        XCTAssertFalse(TargetCfgExpression.parse("x86_64-apple-darwin").matches(target))
    }

    func testUnparseablePredicatesDoNotMatch() {
        XCTAssertFalse(TargetCfgExpression.parse("cfg(target_os = )").matches(target))
        XCTAssertEqual(
            TargetCfgExpression.parse("cfg(target_os = )"),
            .unsupported("cfg(target_os = )")
        )
    }
}
