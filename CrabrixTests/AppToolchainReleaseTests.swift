import CryptoKit
import XCTest
@testable import Crabrix

final class AppToolchainReleaseTests: XCTestCase {
    func testReleaseInputMatchesBundledCompilerAndSysroot() throws {
        let release = try XCTUnwrap(CargoToolchain.release)
        XCTAssertEqual(release.toolchainID, CargoToolchain.bundledVersion)
        XCTAssertEqual(release.target, "wasm32-wasip1")
        XCTAssertEqual(release.rustVersion, CargoToolchain.semanticVersionLabel)
        XCTAssertEqual(
            CargoToolchain.artifactIdentity,
            release.rustcSHA256 + ":" + release.sysrootManifestSHA256
        )

        let bundled = try XCTUnwrap(BundledToolchain.locate(
            in: .main, version: release.toolchainID, prepareSysroot: false
        ))
        let root = bundled.rustcURL.deletingLastPathComponent()
        let archive = root.appending(path: "sysroot-wasip1.zip")
        let checksum = try String(contentsOf: root.appending(path: "sysroot-wasip1.sha256"), encoding: .utf8)
        XCTAssertEqual(checksum.trimmingCharacters(in: .whitespacesAndNewlines), release.sysrootArchiveSHA256)
        XCTAssertEqual(try sha256(bundled.rustcURL), release.rustcSHA256)
        XCTAssertEqual(try sha256(archive), release.sysrootArchiveSHA256)
    }

    private func sha256(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
