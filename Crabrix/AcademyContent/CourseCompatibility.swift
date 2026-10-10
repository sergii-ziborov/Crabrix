import Foundation

enum CourseCompatibility {
    static let supportedCapabilities: Set<String> = [
        "coursepack-v1", "examples-gallery-v1", "lesson-illustrations-v1"
    ]

    static func requireSupported(_ descriptor: CourseDescriptorPayload,
                                 appVersion: SemanticVersion) throws {
        guard let minimum = SemanticVersion(descriptor.minimumAppVersion) else {
            throw CoursePackError.invalidEnvelope
        }
        guard appVersion >= minimum else {
            throw CoursePackError.incompatibleCapability("Crabrix \(minimum) or later")
        }
        for capability in descriptor.requiredCapabilities
            where !supportedCapabilities.contains(capability) {
            throw CoursePackError.incompatibleCapability(capability)
        }
    }

    static func supports(_ entry: CourseCatalogPayload.Entry,
                         appVersion: SemanticVersion) -> Bool {
        guard let minimum = SemanticVersion(entry.minimumAppVersion),
              appVersion >= minimum,
              entry.archiveBytes > 0,
              entry.archiveBytes <= CoursePackVerifier.maximumArchiveBytes else { return false }
        return entry.requiredCapabilities.allSatisfy(supportedCapabilities.contains)
    }
}

/// Selects a single installable version per course. Comparing signed content
/// versions keeps a previously installed lesson from being replaced by an
/// older entry when the catalog adds another release.
enum CourseUpdatePlanner {
    static func latestCompatible(
        in catalog: CourseCatalogPayload?, appVersion: SemanticVersion
    ) -> [String: CourseCatalogPayload.Entry] {
        guard let catalog else { return [:] }
        var latest: [String: CourseCatalogPayload.Entry] = [:]
        for entry in catalog.courses where CourseCompatibility.supports(entry, appVersion: appVersion) {
            guard let version = SemanticVersion(entry.contentVersion) else { continue }
            let key = "\(entry.courseID)|\(entry.language)"
            if let previous = latest[key],
               let previousVersion = SemanticVersion(previous.contentVersion),
               previousVersion >= version { continue }
            latest[key] = entry
        }
        return latest
    }

    static func updates(
        latest: [String: CourseCatalogPayload.Entry], installedVersions: [String: String]
    ) -> [CourseCatalogPayload.Entry] {
        latest.compactMap { key, entry in
            guard let installed = installedVersions[key],
                  let currentVersion = SemanticVersion(installed),
                  let availableVersion = SemanticVersion(entry.contentVersion),
                  availableVersion > currentVersion else { return nil }
            return entry
        }
    }
}
