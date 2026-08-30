import Foundation
import ImageIO
import UIKit

/// A private, device-local profile image.
///
/// The photo picker returns attacker-influenced bytes just like any other file
/// importer. Crabrix validates dimensions, downsamples through ImageIO, and
/// stores only its own bounded JPEG rather than retaining the original asset.
@MainActor
final class LocalAvatarStore: ObservableObject {
    enum AvatarError: LocalizedError {
        case empty
        case tooLarge
        case unsupported
        case unreasonableDimensions
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .empty:
                "The selected image is empty."
            case .tooLarge:
                "Choose an image smaller than 20 MB."
            case .unsupported:
                "That file is not a supported image."
            case .unreasonableDimensions:
                "That image is too large to process safely."
            case .encodingFailed:
                "The image could not be prepared as an avatar."
            }
        }
    }

    nonisolated static let maximumSourceBytes = 20 * 1_024 * 1_024
    nonisolated static let maximumSourcePixels = 100_000_000
    nonisolated static let avatarPixelSize = 512

    @Published private(set) var image: UIImage?
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?

    private let storageURL: URL
    private let fileManager: FileManager

    init(
        storageURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.storageURL = applicationSupport
                .appending(path: "Crabrix", directoryHint: .isDirectory)
                .appending(path: "profile", directoryHint: .isDirectory)
                .appending(path: "avatar.jpg")
        }
        image = UIImage(contentsOfFile: self.storageURL.path)
    }

    var hasCustomAvatar: Bool { image != nil }

    func importImageData(_ data: Data) async {
        isImporting = true
        errorMessage = nil
        do {
            let encoded = try await Task.detached(priority: .userInitiated) {
                try Self.normalizedJPEG(from: data)
            }.value
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoded.write(to: storageURL, options: .atomic)
            guard let decoded = UIImage(data: encoded) else {
                throw AvatarError.encodingFailed
            }
            image = decoded
        } catch {
            errorMessage = error.localizedDescription
        }
        isImporting = false
    }

    func removeAvatar() {
        do {
            if fileManager.fileExists(atPath: storageURL.path) {
                try fileManager.removeItem(at: storageURL)
            }
            image = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    nonisolated static func normalizedJPEG(from data: Data) throws -> Data {
        guard !data.isEmpty else { throw AvatarError.empty }
        guard data.count <= maximumSourceBytes else { throw AvatarError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else {
            throw AvatarError.unsupported
        }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any],
           let width = numericValue(properties[kCGImagePropertyPixelWidth]),
           let height = numericValue(properties[kCGImagePropertyPixelHeight]) {
            guard width > 0,
                  height > 0,
                  width <= 50_000,
                  height <= 50_000,
                  width <= maximumSourcePixels / height
            else {
                throw AvatarError.unreasonableDimensions
            }
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: avatarPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ),
        let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.86)
        else {
            throw AvatarError.encodingFailed
        }
        return jpeg
    }

    nonisolated private static func numericValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            number.intValue
        case let value as Int:
            value
        default:
            nil
        }
    }
}
