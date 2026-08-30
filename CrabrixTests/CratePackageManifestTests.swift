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
        XCTAssertFalse(manifest.buildScriptDisabled)
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
        XCTAssertFalse(manifest.buildScriptDisabled)
        XCTAssertFalse(manifest.isProcMacro)
    }

    func testDetectsImplicitBuildScriptUnlessManifestDisablesIt() throws {
        let omitted = try CratePackageManifest.parse("""
        [package]
        name = "implicit"
        version = "1.0.0"
        """)
        XCTAssertEqual(
            omitted.detectingImplicitBuildScript(fileExists: true).buildScriptPath,
            "build.rs"
        )

        let disabled = try CratePackageManifest.parse("""
        [package]
        name = "disabled"
        version = "1.0.0"
        build = false
        """)
        XCTAssertTrue(disabled.buildScriptDisabled)
        XCTAssertNil(disabled.detectingImplicitBuildScript(fileExists: true).buildScriptPath)
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

    func testValidatesEditionAndResolverVersion() throws {
        let manifest = try CratePackageManifest.parse("""
        [package]
        name = "edition-test"
        version = "0.1.0"
        edition = "2018"
        resolver = "2"
        """)
        XCTAssertEqual(manifest.edition, "2018")
        XCTAssertEqual(manifest.resolverVersion, .v2)

        XCTAssertThrowsError(try CratePackageManifest.parse("""
        [package]
        name = "future"
        version = "0.1.0"
        edition = "2099"
        """)) { error in
            XCTAssertEqual(error as? CratePackageManifestError, .unsupportedEdition("2099"))
        }
    }

    func testRejectsWorkspaceInheritanceAndInvalidDependencyRequirements() {
        XCTAssertThrowsError(try CratePackageManifest.parse("""
        [package]
        name = "member"
        version.workspace = true
        """)) { error in
            XCTAssertEqual(
                error as? CratePackageManifestError,
                .unsupportedWorkspaceInheritance("package.version")
            )
        }

        XCTAssertThrowsError(try CratePackageManifest.parse("""
        [package]
        name = "member"
        version = "1.0.0"

        [dependencies]
        inherited.workspace = true
        """)) { error in
            XCTAssertEqual(
                error as? CratePackageManifestError,
                .unsupportedWorkspaceInheritance("dependencies.inherited")
            )
        }

        XCTAssertThrowsError(try CratePackageManifest.parse("""
        [package]
        name = "broken"
        version = "1.0.0"

        [dependencies]
        serde = { features = ["derive"] }
        """)) { error in
            XCTAssertEqual(
                error as? CratePackageManifestError,
                .missingRegistryDependencyVersion("serde")
            )
        }
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

    func testUnknownPropagatesThroughNotAllAndAny() {
        let unknown = TargetCfgExpression.unsupported("cfg(unmodelled)")
        XCTAssertEqual(
            TargetCfgExpression.not(unknown).matchResult(target),
            .unknown(reason: "Could not evaluate target predicate \"cfg(unmodelled)\".")
        )
        XCTAssertEqual(
            TargetCfgExpression.all([.flag("target_has_atomic"), unknown]).matchResult(target),
            .unknown(reason: "Could not evaluate target predicate \"cfg(unmodelled)\".")
        )
        XCTAssertEqual(
            TargetCfgExpression.any([.flag("windows"), unknown]).matchResult(target),
            .unknown(reason: "Could not evaluate target predicate \"cfg(unmodelled)\".")
        )
    }
}
