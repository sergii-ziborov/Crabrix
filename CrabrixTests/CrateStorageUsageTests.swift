import XCTest
@testable import Crabrix

final class CrateStorageUsageTests: XCTestCase {
    func testMeasuresDependencyAndProjectBuildCachesTogether() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "crabrix-storage-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let archives = root.appending(path: "archives", directoryHint: .isDirectory)
        let sources = root.appending(path: "src", directoryHint: .isDirectory)
        let artifacts = root.appending(path: "artifacts", directoryHint: .isDirectory)
        let projectArtifacts = root.appending(path: "programs", directoryHint: .isDirectory)
        let index = root.appending(path: "index", directoryHint: .isDirectory)

        try write(bytes: 11, to: archives.appending(path: "demo.crate"))
        try write(bytes: 13, to: sources.appending(path: "demo-1.0.0/Cargo.toml"))
        try write(bytes: 17, to: sources.appending(path: ".staging-part/Cargo.toml"))
        try write(bytes: 7, to: artifacts.appending(path: "libdemo.rlib"))
        try write(bytes: 19, to: projectArtifacts.appending(path: "program.wasm"))
        try write(bytes: 5, to: index.appending(path: "de/mo/demo"))

        let usage = CrateStorageUsage.measure(
            archiveDirectory: archives,
            sourceDirectory: sources,
            artifactDirectory: artifacts,
            projectArtifactDirectory: projectArtifacts,
            indexDirectory: index
        )

        XCTAssertEqual(usage.archiveBytes, 11)
        XCTAssertEqual(usage.sourceBytes, 30)
        XCTAssertEqual(usage.artifactBytes, 7)
        XCTAssertEqual(usage.projectArtifactBytes, 19)
        XCTAssertEqual(usage.buildArtifactBytes, 26)
        XCTAssertEqual(usage.indexBytes, 5)
        XCTAssertEqual(usage.totalBytes, 72)
        XCTAssertEqual(usage.packageCount, 1)
    }

    private func write(bytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xA5, count: bytes).write(to: url)
    }
}
