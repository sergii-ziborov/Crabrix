import UIKit
import XCTest
@testable import Crabrix

@MainActor
final class LocalAvatarStoreTests: XCTestCase {
    func testAvatarIsDownsampledPersistedAndReloaded() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Avatar-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let avatarURL = root.appending(path: "avatar.jpg")
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1_200, height: 800))
            .jpegData(withCompressionQuality: 1) { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 800))
            }

        let store = LocalAvatarStore(storageURL: avatarURL)
        await store.importImageData(source)

        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.hasCustomAvatar)
        XCTAssertTrue(FileManager.default.fileExists(atPath: avatarURL.path))
        XCTAssertLessThanOrEqual(store.image?.size.width ?? .infinity, 512)
        XCTAssertLessThanOrEqual(store.image?.size.height ?? .infinity, 512)

        let reloaded = LocalAvatarStore(storageURL: avatarURL)
        XCTAssertTrue(reloaded.hasCustomAvatar)
        reloaded.removeAvatar()
        XCTAssertFalse(reloaded.hasCustomAvatar)
        XCTAssertFalse(FileManager.default.fileExists(atPath: avatarURL.path))
    }

    func testAvatarRejectsInvalidAndOversizedInput() async {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Avatar-Reject-\(UUID().uuidString)")
        let store = LocalAvatarStore(storageURL: root)

        await store.importImageData(Data("not an image".utf8))
        XCTAssertFalse(store.hasCustomAvatar)
        XCTAssertNotNil(store.errorMessage)

        await store.importImageData(
            Data(repeating: 0, count: LocalAvatarStore.maximumSourceBytes + 1)
        )
        XCTAssertFalse(store.hasCustomAvatar)
        XCTAssertEqual(
            store.errorMessage,
            LocalAvatarStore.AvatarError.tooLarge.localizedDescription
        )
    }
}

private extension UIGraphicsImageRenderer {
    func jpegData(
        withCompressionQuality quality: CGFloat,
        actions: (UIGraphicsImageRendererContext) -> Void
    ) -> Data {
        image(actions: actions).jpegData(compressionQuality: quality) ?? Data()
    }
}
