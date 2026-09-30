import Foundation
import XCTest
@testable import Crabrix

final class CourseBootstrapTests: XCTestCase {
    func testBundledBaselineInstallsOfflineAndRelaunchKeepsIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            if FileManager.default.fileExists(atPath: root.path) {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let bootstrap = try CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        )
        let first = try await bootstrap.activateBundledBaseline()
        let second = try await bootstrap.activateBundledBaseline()
        XCTAssertEqual(first.courses.map(\.id), second.courses.map(\.id))
        XCTAssertEqual(first.courses.flatMap(\.units).flatMap(\.lessons).count, 742)
        XCTAssertEqual(
            first.loaded.mapValues(\.archiveSHA256), second.loaded.mapValues(\.archiveSHA256)
        )
    }
}
