import XCTest
import CryptoKit
import ZIPFoundation
@testable import Crabrix

final class BundledSysrootTests: XCTestCase {
    private var work: URL!
    private var archive: URL!
    private var checksum: String!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let source = work.appending(path: "source")
        let root = source.appending(path: "sysroot-wasip1")
        try FileManager.default.createDirectory(
            at: root.appending(path: "lib/rustlib/wasm32-wasip1/lib"), withIntermediateDirectories: true
        )
        try #"{"files":["lib/rustlib/wasm32-wasip1/lib/test.rlib"]}"#.write(to: root.appending(path: "manifest.json"), atomically: true, encoding: .utf8)
        try "WASI compiler data".write(
            to: root.appending(path: "lib/rustlib/wasm32-wasip1/lib/test.rlib"),
            atomically: true, encoding: .utf8
        )
        archive = work.appending(path: "sysroot.zip")
        try FileManager.default.zipItem(at: source, to: archive, shouldKeepParent: false)
        checksum = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    func testBundledDataInstallsAndRehydratesAfterCacheEviction() throws {
        let destination = work.appending(path: "cache/toolchain")
        for _ in 0..<2 {
            try BundledSysroot.prepare(archive: archive, checksum: checksum, at: destination)
            let library = destination.appending(path: "sysroot-wasip1/lib/rustlib/wasm32-wasip1/lib/test.rlib")
            XCTAssertEqual(try String(contentsOf: library, encoding: .utf8), "WASI compiler data")
            XCTAssertEqual(try String(contentsOf: destination.appending(path: ".complete"), encoding: .utf8), checksum)
            try FileManager.default.removeItem(at: destination)
        }
    }

    func testPartialCacheEvictionRehydratesMissingLibrary() throws {
        let destination = work.appending(path: "cache/toolchain")
        try BundledSysroot.prepare(archive: archive, checksum: checksum, at: destination)
        let library = destination.appending(path: "sysroot-wasip1/lib/rustlib/wasm32-wasip1/lib/test.rlib")
        try FileManager.default.removeItem(at: library)
        try BundledSysroot.prepare(archive: archive, checksum: checksum, at: destination)
        XCTAssertEqual(try String(contentsOf: library, encoding: .utf8), "WASI compiler data")
    }

    func testCorruptBundledArchiveCannotBecomeAnInstalledToolchain() throws {
        let destination = work.appending(path: "cache/toolchain")
        XCTAssertThrowsError(try BundledSysroot.prepare(archive: archive, checksum: "incorrect", at: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testInterruptedInstallationIsReplacedFromBundledData() throws {
        let destination = work.appending(path: "cache/toolchain")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "partial".write(to: destination.appending(path: "unfinished"), atomically: true, encoding: .utf8)
        try BundledSysroot.prepare(archive: archive, checksum: checksum, at: destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appending(path: "unfinished").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appending(path: ".complete").path))
    }
}
