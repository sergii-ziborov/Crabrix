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
}
