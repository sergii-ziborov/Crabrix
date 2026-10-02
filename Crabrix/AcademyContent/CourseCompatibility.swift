import Foundation

enum CourseCompatibility {
    static func requireSupported(_ descriptor: CourseDescriptorPayload,
                                 appVersion: SemanticVersion) throws {
        guard let minimum = SemanticVersion(descriptor.minimumAppVersion) else {
            throw CoursePackError.invalidEnvelope
        }
        guard appVersion >= minimum else {
            throw CoursePackError.incompatibleCapability("Crabrix \(minimum) or later")
        }
        for capability in descriptor.requiredCapabilities where capability != "coursepack-v1" {
            throw CoursePackError.incompatibleCapability(capability)
        }
    }
}
