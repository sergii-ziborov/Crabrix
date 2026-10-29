import Foundation

/// Stable, source-assigned reasons. Never guess a platform requirement by
/// searching compiler diagnostics or a crate's name.
enum LocalExecutionReason: String, Codable, Sendable, CaseIterable {
    case unspecifiedRequirement = "unspecified-requirement"
    case nativeLinkMetadata = "native-link-metadata"
    case proceduralMacroHost = "procedural-macro-host"
    case proceduralMacroFeature = "procedural-macro-feature"
    case unsupportedLibraryTarget = "unsupported-library-target"
    case missingLibraryTarget = "missing-library-target"
    case buildDependencyGraph = "build-dependency-graph"
    case sourceAccess = "source-access"
    case invalidFiles = "invalid-files"
    case invalidManifest = "invalid-manifest"
    case virtualWorkspace = "virtual-workspace"
    case minimumRustVersion = "minimum-rust-version"
    case libraryEntry = "library-entry"
    case cargoConfiguration = "cargo-configuration"
    case unpreparedGraph = "unprepared-graph"
    case unresolvedDependency = "unresolved-dependency"
    case previousCompilerFailure = "previous-compiler-failure"
    case browserDebugger = "browser-debugger"
    case toolchainUnavailable = "toolchain-unavailable"
    case buildScriptReview = "build-script-review"
    case profileInformation = "profile-information"

    enum Category: String, Codable, Sendable {
        case requirement, preparation, input, previousAttempt, information
    }
    var category: Category {
        switch self {
        case .nativeLinkMetadata, .proceduralMacroHost, .proceduralMacroFeature,
             .unsupportedLibraryTarget, .missingLibraryTarget, .buildDependencyGraph,
             .virtualWorkspace, .minimumRustVersion, .libraryEntry, .cargoConfiguration,
             .browserDebugger, .unspecifiedRequirement: .requirement
        case .unpreparedGraph, .unresolvedDependency, .toolchainUnavailable: .preparation
        case .sourceAccess, .invalidFiles, .invalidManifest: .input
        case .previousCompilerFailure: .previousAttempt
        case .buildScriptReview, .profileInformation: .information
        }
    }
    var nextStep: String? {
        switch self {
        case .nativeLinkMetadata:
            "Inspect the declared native-link requirement and exact features. Adapt an editable copy to a supported pure-Rust/WASI alternative; no native library is supplied automatically."
        case .proceduralMacroHost, .proceduralMacroFeature:
            "Inspect the exact macro/feature requirement. Parser-only features can be useful for parsing tasks, but are not a substitute for executing a required procedural macro."
        case .unsupportedLibraryTarget:
            "Select a supported binary or rlib target in an editable copy. The requested target will not be silently replaced."
        case .missingLibraryTarget:
            "Inspect this package's declared targets. A binary-only package cannot be linked as a dependency library."
        case .buildDependencyGraph:
            "Review build.rs and its build-dependencies. The current std-only script profile cannot supply a separate host dependency graph."
        case .sourceAccess, .invalidFiles:
            "Review the named path and source limits. Keep a local/exported copy before deliberately reducing or adapting the project."
        case .invalidManifest:
            "Correct the manifest diagnostic first, then inspect again. No compiler result has been inferred from invalid input."
        case .virtualWorkspace:
            "Select the intended workspace member; inspect its own manifest, entry and resolved graph."
        case .minimumRustVersion:
            "Compare the package's rust-version with the bundled compiler. Choose a compatible version or a qualified newer toolchain."
        case .libraryEntry:
            "Use Check or rlib Build for this entry, or explicitly select a binary entry for Run/Debug."
        case .cargoConfiguration:
            "Review the named configuration in an editable copy. Fixed-target overrides are not silently ignored or applied to the host."
        case .unpreparedGraph, .unresolvedDependency:
            "Prepare or repair the exact current dependency graph explicitly. This inspection never downloads or executes packages."
        case .previousCompilerFailure:
            "Read the original diagnostic and retry or reduce it to a reproducer. A failed attempt is not proof of an unsupported platform."
        case .browserDebugger:
            "Use the local Web Preview console for JavaScript. Rust source Debug needs a Rust entry."
        case .toolchainUnavailable:
            "Restore the bundled compiler resources or update the app before retrying. Inspection cannot establish a working compiler."
        case .buildScriptReview:
            "Inspect the script's actual requirements, then perform a deliberate local build. Static inspection is not successful execution evidence."
        case .unspecifiedRequirement:
            "Inspect the recorded requirement. Its text is retained without guessing a more specific platform cause."
        case .profileInformation: nil
        }
    }
}
