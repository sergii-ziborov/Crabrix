import Foundation

/// A separate, immutable compiler input. No ProjectModel, prepared package
/// directory, binary resource, local overlay or environment can be attached.
struct PlaygroundRuntimeInput: Sendable {
    enum Operation: String, Codable, Sendable { case check, build, run, debug }
    static let profile = "shared-std-v1"
    let source: String
    let sourcePath: String
    let supportingFiles: [String: String]
    let edition: String

    @MainActor
    init(document: PlaygroundDocument) throws {
        // Use the same signed codec validation as the room/source revision,
        // including Unicode path aliases before a native dictionary is used.
        let codec = try PlaygroundCodec()
        guard let room = try codec.initialize(document).document else {
            throw PlaygroundFailure("The shared source could not be validated.")
        }
        let files = room.files
        guard !files.keys.contains(where: { ($0 as NSString).lastPathComponent.lowercased() == "build.rs" || $0 != "Cargo.toml" && ($0 as NSString).lastPathComponent.lowercased() == "cargo.toml" }) else {
            throw PlaygroundFailure("Shared execution supports the standard library and local modules. Build scripts and nested Cargo packages need an ordinary local project run.")
        }
        if let text = files["Cargo.toml"] {
            let manifest = try CratePackageManifest.parse(text)
            let cargo = try TOMLParser.parse(text)
            // This is an explicitly small selected-entry profile. Reject
            // requirements instead of silently ignoring Cargo configuration.
            guard Set(cargo.keys).isSubset(of: ["package", "bin", "lib"]),
                  let package = cargo["package"]?.tableValue,
                  Set(package.keys).isSubset(of: ["name", "version", "edition", "authors", "description", "license", "license-file", "repository", "homepage", "documentation", "keywords", "categories", "readme", "publish", "include", "exclude", "build"]),
                  !manifest.packageName.isEmpty, manifest.version != nil,
                  manifest.edition == room.edition, manifest.dependencies.isEmpty,
                  !manifest.isVirtualWorkspace, !manifest.isProcMacro,
                  !manifest.requiresUnsupportedCrateType, manifest.links == nil,
                  manifest.buildScriptPath == nil,
                  package["build"] == nil || package["build"]?.boolValue == false else {
                throw PlaygroundFailure("Shared execution needs a single Cargo package with explicit matching edition and no dependencies, features, workspace, native links or build script. Nothing was downloaded or omitted.")
            }
            if let bin = cargo["bin"] {
                guard cargo["lib"] == nil, let targets = bin.arrayValue, targets.count == 1,
                      let target = targets.first?.tableValue,
                      Set(target.keys).isSubset(of: ["name", "path"]),
                      target["name"] == nil || target["name"]?.stringValue != nil,
                      target["path"] == nil || target["path"]?.stringValue != nil,
                      (target["path"]?.stringValue ?? "src/main.rs") == room.entryFile else {
                    throw PlaygroundFailure("Shared execution needs one binary target matching the selected entry file.")
                }
            }
            if let lib = cargo["lib"] {
                guard let target = lib.tableValue,
                      Set(target.keys).isSubset(of: ["name", "path", "crate-type"]),
                      target["name"] == nil || target["name"]?.stringValue != nil,
                      target["path"] == nil || target["path"]?.stringValue != nil,
                      (target["path"]?.stringValue ?? "src/lib.rs") == room.entryFile,
                      target["crate-type"] == nil || target["crate-type"]?.arrayValue?.allSatisfy({ $0.stringValue != nil }) == true,
                      manifest.library.crateTypes.allSatisfy({ ["lib", "rlib"].contains($0) }) else {
                    throw PlaygroundFailure("Shared execution supports a selected Rust library, without native or procedural-macro crate types.")
                }
            }
        }
        sourcePath = room.entryFile
        source = files[sourcePath]!
        supportingFiles = files.filter { $0.key != room.entryFile }
        edition = room.edition
    }

    func execute(_ operation: Operation, compiler: WasmRustCompiler,
                 cancellation: CompilerInvocationCancellation,
                 debugSession: RustDebugSession? = nil,
                 onStage: (@Sendable (String) -> Void)? = nil) async -> CompilationResult {
        var result: CompilationResult
        switch operation {
        case .check:
            result = await compiler.check(source: source, sourcePath: sourcePath, supportingFiles: supportingFiles,
                resourceFiles: [:], edition: edition, plan: .empty, cancellation: cancellation, onStage: onStage)
        case .build:
            result = await compiler.build(source: source, sourcePath: sourcePath, supportingFiles: supportingFiles,
                resourceFiles: [:], edition: edition, plan: .empty, cancellation: cancellation, onStage: onStage)
        case .run:
            result = await compiler.run(source: source, sourcePath: sourcePath, supportingFiles: supportingFiles,
                resourceFiles: [:], edition: edition, plan: .empty, cancellation: cancellation, onStage: onStage)
        case .debug:
            guard let debugSession else { return .failure(phase: .setup, detail: "Shared Debug needs its own local session.") }
            result = await compiler.debug(source: source, sourcePath: sourcePath, supportingFiles: supportingFiles,
                resourceFiles: [:], edition: edition, plan: .empty, session: debugSession, cancellation: cancellation, onStage: onStage)
        }
        // Shared execution has no generated-asset transfer or saved-project
        // build evidence. Ordinary local Rust + Web execution is unaffected.
        result.webPreview = nil
        return result
    }
}
