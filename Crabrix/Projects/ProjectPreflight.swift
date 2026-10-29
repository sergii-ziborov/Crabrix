import CryptoKit
import Foundation

/// Bind stored evidence to every bundled compiler used by a project. Merely
/// opening a web preview does not prove that its JavaScript ran successfully.
enum ProjectExecutionProfile {
    static let browserIdentity: String = {
        var hasher = SHA256()
        for name in ["WebCompilerRuntime", "WebProjectBuilder"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
                  let data = try? Data(contentsOf: url) else { return "unavailable" }
            hasher.update(data: Data(name.utf8)); hasher.update(data: data)
        }
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "TypeScriptCore"),
              let data = try? Data(contentsOf: url) else { return "unavailable" }
        hasher.update(data: data)
        return "browser-bundle-types-v2:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }()
    static var identity: String { WasmRustCompiler.executionIdentity + ":" + browserIdentity }
}

struct ProjectPreflight: Sendable {
    enum State: String, Sendable { case unverified, verified, blocked }
    enum Origin: String, Sendable {
        case files = "Project files", manifest = "Cargo manifest", graph = "Prepared Cargo graph"
        case profile = "Local execution profile", browser = "Browser compiler", evidence = "Recorded result"
    }
    struct Issue: Identifiable, Sendable {
        let origin: Origin
        let detail: String
        let blocked: Set<ProjectVerifiedOperation>
        let code: LocalExecutionReason
        let subject: String?
        var nextStep: String? { code.nextStep }
        var id: String { code.rawValue + ":" + (subject ?? "") + ":" + origin.rawValue + ":" + detail }
    }
    struct Operation: Identifiable, Sendable {
        let kind: ProjectVerifiedOperation
        let title: String
        let state: State
        let detail: String
        var id: String { kind.rawValue }
    }
    struct Input: Sendable {
        let project: CrabrixProject
        let revision: WorkspaceRevision
        let workspace: CargoWorkspaceSnapshot
        let graphIsCurrent: Bool
        let lastBuild: ProjectBuildRecord?
        var browserDirectory: String? = nil
    }
    struct Dependency: Identifiable, Sendable {
        let package: String
        let features: [String]
        let fingerprint: String?
        let status: String
        let sourcePrepared: Bool
        var id: String { package }
    }
    let revision: WorkspaceRevision
    let target: String
    let entry: String
    let edition: String?
    let features: [String]?
    let graphSummary: String
    let dependencies: [Dependency]
    let operations: [Operation]
    let issues: [Issue]
    let filesAccepted: Bool

    func blockingReason(for operation: ProjectVerifiedOperation) -> String? {
        issues.first { $0.blocked.contains(operation) }.map { "\($0.origin.rawValue): \($0.detail)" }
    }

    /// Inspection only: no resolver, network access, compiler invocation or
    /// project mutation. Call off the main actor for large imported trees.
    static func inspect(_ input: Input) -> Self {
        let project = input.project
        let browser = input.browserDirectory != nil || BrowserProjectConfiguration.isBrowserEntry(project.entryFile)
        let browserEntry = BrowserProjectConfiguration.entry(files: project.files, preferred: project.entryFile, directory: input.browserDirectory)
        let typedBrowser = browser && BrowserTypeScriptProfile.applies(files: project.files,
            directory: BrowserTypeScriptProfile.directory(files: project.files, entry: browserEntry))
        let all = Set(ProjectVerifiedOperation.allCases)
        var issues: [Issue] = []
        func issue(_ origin: Origin, _ detail: String, blocks: Set<ProjectVerifiedOperation> = [],
                   code: LocalExecutionReason = .profileInformation, subject: String? = nil) {
            issues.append(.init(origin: origin, detail: detail, blocked: blocks, code: code, subject: subject))
        }
        var filesAccepted = true
        do { try ProjectFilePolicy.validate(project.files, entryFile: project.entryFile) }
        catch { filesAccepted = false; issue(.files, error.localizedDescription, blocks: all, code: .invalidFiles, subject: fileFailurePath(error)) }
        var edition: String?
        var features: [String]?
        var graph = "No Cargo manifest; standalone Rust source."
        var dependencies: [Dependency] = []
        if browser {
            graph = "Only already prepared browser modules are used by Check, Build and Run. npm install / ci is a separate, explicit preparation step."
            if ProjectExecutionProfile.browserIdentity == "unavailable" {
                issue(.browser, "The bundled browser compiler is unavailable.", blocks: all, code: .toolchainUnavailable)
            }
            issue(.browser, typedBrowser
                ? "Check uses bundled TypeScript \(BrowserTypeScriptProfile.version), standard libraries and prepared declarations, followed by browser bundling. Missing types require explicit preparation. Run and Build transpile/bundle separately; opening a Web Preview does not prove successful JavaScript execution."
                : "Check parses and bundles browser modules. This project has no TypeScript checking input. A Web Preview opening is not evidence of successful JavaScript execution.")
            issue(.profile, "Rust Debug is unavailable for a browser entry. Use Run and the Web Preview console.", blocks: [.debug], code: .browserDebugger, subject: browserEntry)
        } else if let text = project.files["Cargo.toml"] {
            do {
                let manifest = try CratePackageManifest.parse(text).detectingImplicitBuildScript(fileExists: project.files["build.rs"] != nil)
                edition = manifest.edition
                if manifest.isVirtualWorkspace {
                    issue(.manifest, "Select a package member before building this virtual workspace.", blocks: all, code: .virtualWorkspace, subject: "Cargo.toml")
                }
                if let required = manifest.rustVersion {
                    if let version = SemanticVersion(required), version <= CargoToolchain.semanticVersion { }
                    else { issue(.manifest, "This package requires Rust \(required); bundled rustc is \(CargoToolchain.semanticVersionLabel).", blocks: all, code: .minimumRustVersion, subject: "Cargo.toml") }
                }
                let library = project.entryFile == manifest.library.path || project.entryFile == "lib.rs" || project.entryFile.hasSuffix("/lib.rs")
                if library {
                    issue(.profile, "This entry is a library. Check and rlib Build are separate from running a binary entry.", blocks: [.run, .debug], code: .libraryEntry, subject: project.entryFile)
                    if manifest.library.isProcMacro || manifest.library.crateTypes.contains(where: { !["lib", "rlib"].contains($0) }) {
                        issue(.manifest, "Compile-only Build supports an rlib entry; this manifest requests a different library target. It will not be substituted.", blocks: [.build], code: .unsupportedLibraryTarget, subject: "Cargo.toml")
                    }
                }
                if let script = manifest.buildScriptPath {
                    let dependencies = manifest.dependencies.filter { $0.kind == .build && $0.applies(to: .wasm32WasiP1) }.map(\.alias).sorted()
                    if !dependencies.isEmpty {
                        issue(.manifest, "\(script) needs a separate build-dependency host graph: \(dependencies.joined(separator: ", ")). This profile cannot supply it.", blocks: all, code: .buildDependencyGraph, subject: script)
                    } else {
                        issue(.profile, "\(script) runs in the local std-only WASI profile. Host subprocesses and native linking are unavailable; script execution is still unverified.", code: .buildScriptReview, subject: script)
                    }
                }
                if input.graphIsCurrent {
                    features = input.workspace.plan.rootFeatures
                    graph = input.workspace.summary + (input.workspace.isOfflineReady ? " · sources prepared offline" : " · source preparation incomplete")
                    for package in input.workspace.packages {
                        dependencies.append(.init(package: package.package.description, features: package.features,
                            fingerprint: input.workspace.plan.units.first { $0.package == package.package }?.fingerprint,
                            status: package.compatibility.label, sourcePrepared: package.isDownloaded))
                        if let detail = package.compatibility.detail {
                            if case .buildFailed = package.compatibility {
                                issue(.evidence, "\(package.package): previous compiler attempt failed: \(detail). This is not a proven platform restriction; retrying is allowed.", code: .previousCompilerFailure, subject: package.package.description)
                            } else {
                                issue(.graph, "\(package.package): \(detail)", blocks: package.compatibility.isBlocking ? all : [], code: package.compatibility.reasonCode ?? .profileInformation, subject: package.package.description)
                            }
                        }
                    }
                    for reason in input.workspace.unresolvedDependencies { issue(.graph, reason, blocks: all, code: .unresolvedDependency) }
                    for warning in input.workspace.warnings { issue(.graph, warning) }
                } else if !manifest.dependencies.isEmpty || !manifest.features.isEmpty {
                    graph = "Current features and dependency fingerprints are not prepared. No package compatibility is inferred from an older graph."
                    issue(.graph, "Prepare the current Cargo inputs to inspect exact resolved versions and features. This report never downloads packages.", code: .unpreparedGraph, subject: "Cargo.toml")
                } else {
                    features = []; graph = "No dependencies or feature declarations."
                }
            } catch { issue(.manifest, error.localizedDescription, blocks: all, code: .invalidManifest, subject: "Cargo.toml") }
        } else { edition = "2024"; features = [] }
        if !browser {
            for path in [".cargo/config", ".cargo/config.toml"] {
                guard let config = project.files[path] else { continue }
                do {
                    let document = try TOMLParser.parse(config)
                    var overrides = [String]()
                    for key in ["target", "rustflags", "rustdocflags"] where document["build"]?[key] != nil { overrides.append("build." + key) }
                    for key in ["env", "source", "registry", "registries", "unstable"] where document[key] != nil { overrides.append(key) }
                    for (target, settings) in document["target"]?.tableValue ?? [:] {
                        // Known non-matching target settings cannot affect the
                        // fixed WASI invocation. Unknown predicates are refused.
                        if TargetCfgExpression.parse(target).matchResult(.wasm32WasiP1) == .no { continue }
                        for key in ["runner", "linker", "rustflags", "rustdocflags"] where settings[key] != nil { overrides.append("target.\(target).\(key)") }
                    }
                    if !overrides.isEmpty {
                        issue(.profile, "\(path) requests configuration outside the fixed WASI invocation: \(overrides.sorted().joined(separator: ", ")). Review and explicitly adapt it in a copy; these settings will not be silently ignored.", blocks: all, code: .cargoConfiguration, subject: path)
                    } else if !document.isEmpty {
                        issue(.profile, "\(path) was inspected. Cargo aliases and host settings do not change this app's fixed compiler invocation.")
                    }
                } catch { issue(.profile, "\(path): \(error.localizedDescription)", blocks: all, code: .invalidManifest, subject: path) }
            }
            issue(.profile, "Target is wasm32-wasip1 with local WASI execution. Native C/C++ libraries, GPU/CUDA, host subprocesses, OS threads and listening TCP servers are not provided. A crate name alone never establishes compatibility.")
        }
        let operations = ProjectVerifiedOperation.allCases.map { operation in
            let blocker = issues.first { $0.blocked.contains(operation) }
            // Web Run records mean that a preview was constructed, not that a
            // browser acknowledged successful execution. Keep that unverified.
            let hasEvidence = input.lastBuild?.verifies(operation, revision: input.revision,
                kind: browser ? .browser : .rust, compilerEntry: browser ? browserEntry : project.entryFile) == true
            let verified: Bool
            if browser {
                switch operation {
                case .check: verified = hasEvidence && (!typedBrowser || (input.lastBuild?.phase == .check && input.lastBuild?.browserTypeCheckVersion == BrowserTypeScriptProfile.version))
                case .build: verified = hasEvidence
                case .run, .debug: verified = false
                }
            } else { verified = hasEvidence }
            let state: State = blocker != nil ? .blocked : verified ? .verified : .unverified
            let detail = blocker?.detail ?? (verified
                ? "Confirmed by the latest successful result for these exact source, resource and compiler identities."
                : browser && operation == .run ? "Run opens a local Web Preview. Runtime success must be checked in its console."
                : "No successful result for this operation and exact current snapshot. Inspection does not execute it.")
            let title = browser && operation == .check ? (typedBrowser ? "Check · TypeScript types and bundle" : "Check · syntax and bundle") : operation.rawValue.capitalized
            return Operation(kind: operation, title: title, state: state, detail: detail)
        }
        return Self(revision: input.revision, target: browser ? "Local browser · HTML / CSS / JavaScript" : RustTargetSpec.wasm32WasiP1.triple,
                    entry: project.entryFile, edition: edition, features: features, graphSummary: graph,
                    dependencies: dependencies, operations: operations, issues: issues, filesAccepted: filesAccepted)
    }
    private static func fileFailurePath(_ error: Error) -> String? {
        guard let failure = error as? ProjectFilePolicy.Failure else { return nil }
        return switch failure {
        case let .unsafePath(path), let .fileTooLarge(path), let .unreadable(path), let .snapshotMismatch(path): path
        case .tooManyFiles, .projectTooLarge, .metadataTooLarge: nil
        }
    }

}

struct CargoFeatureProposal: Identifiable, Sendable {
    let id = UUID()
    let revision: WorkspaceRevision
    let before: [String: String]
    let after: [String: String]
    let backupPath: String
    let removed: [String]
    let inserted: [String]

    init(project: CrabrixProject, revision: WorkspaceRevision) throws {
        guard let original = project.files["Cargo.toml"], original.utf8.count <= 65_536 else {
            throw CargoFeatureError.message("This feature preview needs a Cargo.toml no larger than 64 KiB. Edit a larger custom manifest manually.")
        }
        let updated = try CargoManifestEditor.usingSynParserFeatures(original)
        guard updated != original else { throw CargoFeatureError.message("No standard syn feature change is available. Review this custom dependency in Cargo.toml.") }
        self.revision = revision; before = project.files
        backupPath = ".cargo/crabrix-feature-backups/\(UUID().uuidString.lowercased()).toml"
        var files = project.files; files["Cargo.toml"] = updated; files[backupPath] = original
        try ProjectFilePolicy.validate(files, entryFile: project.entryFile)
        after = files
        // Bounded input; the complete original is kept in the project, while
        // the review displays only differing lines rather than two huge forms.
        let difference = updated.components(separatedBy: "\n").difference(from: original.components(separatedBy: "\n"))
        removed = difference.removals.compactMap { if case let .remove(_, element, _) = $0 { element } else { nil } }
        inserted = difference.insertions.compactMap { if case let .insert(_, element, _) = $0 { element } else { nil } }
    }
}
enum CargoFeatureError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
}
