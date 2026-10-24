import XCTest
@testable import Crabrix

final class CargoBuildScriptTests: XCTestCase {
    func testBothCargoProtocolsKeepArgumentOrderAndEqualsInValues() throws {
        let output = try CargoBuildScriptOutput.parse("""
        ordinary log line
        cargo:rustc-check-cfg=cfg(has_table)
        cargo::rustc-cfg=has_table
        cargo::rustc-env=GENERATED_LABEL=a=b
        cargo:rerun-if-changed=table.csv
        """)
        XCTAssertEqual(output.compilerArguments, ["--check-cfg", "cfg(has_table)", "--cfg", "has_table"])
        XCTAssertEqual(output.environment, ["GENERATED_LABEL": "a=b"])
    }

    func testNativeLinkingAndEnvironmentEscapesAreNotSilentlyIgnored() {
        for line in ["cargo::rustc-link-lib=ssl", "cargo:rustc-flags=-L/private",
                     "cargo:rustc-env=OUT_DIR=/private", "cargo:rustc-env=CARGO_MANIFEST_DIR=/",
                     "cargo:error=generated table is invalid", "cargo::broken"] {
            XCTAssertThrowsError(try CargoBuildScriptOutput.parse(line), line)
        }
    }
}
