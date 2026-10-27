import CryptoKit
import Foundation
import JavaScriptCore

struct BrowserBuildError: LocalizedError, Sendable {
    let message: String
    var file: String = ""
    var line: Int = 1
    var column: Int = 1
    var errorDescription: String? { file.isEmpty ? message : "\(file):\(line):\(column): \(message)" }
}

struct BrowserPackagePin: Codable, Sendable {
    var name: String?
    let version: String
    var resolved: String?
    var integrity: String?
}

private struct BrowserMissingPackage: Decodable, Sendable {
    let name: String
    let directory: String
    let requirements: [String]
    let importer: String
    let locked: BrowserPackagePin?
}

private struct BrowserCompilerReply: Decodable, Sendable {
    struct Failure: Decodable, Sendable {
        let message: String
        let file: String
        let line: Int
        let column: Int
    }
    let error: Failure?
    let missing: BrowserMissingPackage?
    let entry: String?
    let manifestPath: String?
    let assets: [String: String]?
    let usedPaths: [String]?
    let packageRoots: [String]?
    let packageDependencies: [String: [String]]?
    let moduleCount: Int?
}

/// A serial worker owns the trusted compiler tools. Project code is passed as
/// text to the parser; only the generated result runs in WebKit, never here.
final class BrowserJavaScriptCompiler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.crabrix.browser-build", qos: .userInitiated)
    private var context: JSContext?
    private let resourceDirectory: URL?

    init(resourceDirectory: URL? = nil) { self.resourceDirectory = resourceDirectory }

    private func prepareContext() throws -> JSContext {
        if let context { return context }
        guard let created = JSContext() else { throw BrowserBuildError(message: "The offline JavaScript compiler could not start.") }
        for name in ["WebCompilerRuntime", "WebProjectBuilder"] {
            let url = resourceDirectory?.appending(path: name + ".js")
                ?? Bundle.main.url(forResource: name, withExtension: "js")
            guard let url else { throw BrowserBuildError(message: "The app is missing its bundled browser compiler: \(name).") }
            created.evaluateScript(try String(contentsOf: url, encoding: .utf8), withSourceURL: url)
            if let exception = created.exception {
                throw BrowserBuildError(message: "The bundled browser compiler could not load: \(exception.toString() ?? name)")
            }
        }
        context = created
        return created
    }

    fileprivate func build(files: [String: String], entry: String?) async throws -> BrowserCompilerReply {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let context = try prepareContext()
                    context.exception = nil
                    let input = String(decoding: try JSONEncoder().encode(files), as: UTF8.self)
                    let function = context.objectForKeyedSubscript("CrabrixWebBuilder")?.objectForKeyedSubscript("build")
                    guard let value = function?.call(withArguments: [input, entry ?? ""]),
                          context.exception == nil, let text = value.toString() else {
                        throw BrowserBuildError(message: context.exception?.toString() ?? "The browser compiler returned no result.")
                    }
                    continuation.resume(returning: try JSONDecoder().decode(BrowserCompilerReply.self, from: Data(text.utf8)))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    fileprivate func selectVersion(_ versions: [String], requirements: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let context = try prepareContext()
                    context.exception = nil
                    let function = context.objectForKeyedSubscript("CrabrixWebBuilder")?.objectForKeyedSubscript("selectVersion")
                    let result = function?.call(withArguments: [versions, requirements])
                    guard context.exception == nil, let result, !result.isNull, !result.isUndefined,
                          let version = result.toString() else {
                        throw BrowserBuildError(message: "No published npm version satisfies \(requirements.joined(separator: " and ")).")
                    }
                    continuation.resume(returning: version)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

struct PreparedBrowserProject: Sendable {
    let preview: WebPreviewSnapshot
    /// Only selected source modules and their licenses are copied. They remain
    /// ordinary editable project files and survive package-cache eviction.
    let sourceAdditions: [String: String]
    let packageCount: Int
    let moduleCount: Int
    let transfers: [PackageTransferRow]
    let sourceRemovalPrefix: String
}

actor BrowserProjectBuilder {
    static let shared = BrowserProjectBuilder()
    private let compiler: BrowserJavaScriptCompiler
    private let registry: BrowserNpmRegistry

    init(compiler: BrowserJavaScriptCompiler = BrowserJavaScriptCompiler(), registry: BrowserNpmRegistry = BrowserNpmRegistry()) {
        self.compiler = compiler
        self.registry = registry
    }

    /// Run/Check never fetch. Preparation is an explicit, separate command.
    func build(
        files initial: [String: String], preferredEntry: String?,
        preparePackages: Bool = false, frozen: Bool = false,
        onStage: @escaping @Sendable (String) -> Void = { _ in },
        onTransfer: @escaping @Sendable (PackageTransferEvent) -> Void = { _ in }
    ) async throws -> PreparedBrowserProject {
        var files = initial
        let manifestPath = BrowserProjectConfiguration.manifestPath(files: initial, entry: preferredEntry ?? "index.html")
        let root = (manifestPath as NSString).deletingLastPathComponent
        let sourceRemovalPrefix = root.isEmpty ? "node_modules/" : root + "/node_modules/"
        let lockPath = root.isEmpty ? "crabrix-web.lock.json" : root + "/crabrix-web.lock.json"
        let npmLockPath = root.isEmpty ? "package-lock.json" : root + "/package-lock.json"
        if preparePackages { files = files.filter { !$0.key.split(separator: "/").contains("node_modules") } }
        if frozen {
            guard let text = files[npmLockPath],
                  let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  (object["lockfileVersion"] as? Int ?? 0) >= 2 else {
                throw BrowserBuildError(message: "npm ci needs an npm package-lock.json with lockfileVersion 2 or 3.", file: "package-lock.json")
            }
            guard let rootPackage = (object["packages"] as? [String: [String: Any]])?[""],
                  let manifestText = initial[manifestPath],
                  let manifest = try? JSONSerialization.jsonObject(with: Data(manifestText.utf8)) as? [String: Any] else {
                throw BrowserBuildError(message: "npm ci needs the root package entry in package-lock.json.", file: npmLockPath)
            }
            for section in ["dependencies", "devDependencies", "optionalDependencies"] {
                guard (rootPackage[section] as? [String: String] ?? [:]) == (manifest[section] as? [String: String] ?? [:]) else {
                    throw BrowserBuildError(message: "package.json and package-lock.json disagree in \(section). Update the npm lockfile before npm ci.", file: npmLockPath)
                }
            }
            files = files.filter { !$0.key.split(separator: "/").contains("node_modules") && $0.key != lockPath }
        }
        var pins: [String: BrowserPackagePin] = [:]
        var packageIDs: [String: PackageID] = [:]
        var states: [PackageID: PackageTransferRow.State] = [:]
        var edges: [PackageID: Set<PackageID>] = [:]
        var attempted = Set<String>()
        onStage(preparePackages ? "Preparing browser package imports" : "Building local browser modules")
        for _ in 0..<2_048 {
            try Task.checkCancellation()
            let reply = try await compiler.build(files: files, entry: preferredEntry)
            try Task.checkCancellation()
            if let error = reply.error {
                throw BrowserBuildError(message: error.message, file: error.file, line: error.line, column: error.column)
            }
            if let request = reply.missing {
                guard preparePackages else {
                    throw BrowserBuildError(message: "Browser package \(request.name) is not prepared. Run npm install once while connected; subsequent builds run offline.", file: request.importer)
                }
                guard attempted.insert(request.directory).inserted else {
                    throw BrowserBuildError(message: "The package does not provide the requested browser source. Inspect its exports and use a supported browser entry.", file: request.importer)
                }
                guard WebPreviewSnapshot.isSafePath(request.directory), request.directory.contains("node_modules/") else {
                    throw BrowserBuildError(message: "Invalid browser package destination.")
                }
                if frozen, request.locked?.resolved == nil || request.locked?.integrity == nil {
                    throw BrowserBuildError(message: "The npm lockfile has no matching entry for \(request.name). Refresh it with npm on a compatible project or use npm install.", file: "package-lock.json")
                }
                let chosen: BrowserNpmRegistry.Version
                if let locked = request.locked, let url = locked.resolved, let integrity = locked.integrity {
                    chosen = .init(name: request.name, version: locked.version, dist: .init(tarball: url, integrity: integrity, shasum: nil))
                } else {
                    onStage("Resolving npm/\(request.name)")
                    let versions = try await registry.versions(for: request.name)
                    let version = try await compiler.selectVersion(Array(versions.keys), requirements: request.requirements)
                    guard let selected = versions[version] else { throw BrowserBuildError(message: "The npm registry omitted the selected package version.") }
                    chosen = selected
                }
                guard chosen.name == request.name, let version = SemanticVersion(chosen.version) else {
                    throw BrowserBuildError(message: "The npm registry returned an invalid package identity.")
                }
                let id = PackageID(name: "npm/" + request.name, version: version)
                if let parent = packageIDs.keys.filter({ request.importer.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }),
                   let parentID = packageIDs[parent] { edges[parentID, default: []].insert(id) }
                packageIDs[request.directory] = id
                states[id] = .waiting
                onTransfer(.planned(states.keys.sorted().map {
                    PackageTransferRow(package: $0, dependencies: Array(edges[$0] ?? []).sorted(), state: states[$0] ?? .waiting)
                }))
                onStage("Preparing npm/\(chosen.name) \(chosen.version)")
                let result: BrowserNpmRegistry.Source
                do { result = try await registry.source(for: chosen) { state in onTransfer(.updated(id, state)) } }
                catch { onTransfer(.updated(id, .failed(error.localizedDescription))); throw error }
                states[id] = result.cached ? .cached : .ready
                for (relative, source) in result.files {
                    let path = request.directory + "/" + relative
                    let oldManifest = initial[request.directory + "/package.json"].flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                    files[path] = !frozen && oldManifest?["version"] as? String == chosen.version ? (initial[path] ?? source) : source
                }
                guard files.count <= 20_000, files.values.reduce(0, { $0 + $1.utf8.count }) <= 64 * 1024 * 1024 else {
                    throw BrowserBuildError(message: "The temporary browser package sources exceed the 64 MiB preparation budget.")
                }
                pins[request.directory] = BrowserPackagePin(name: chosen.name, version: chosen.version,
                    resolved: chosen.dist.tarball, integrity: result.integrity)
                continue
            }
            guard let entry = reply.entry, let assets = reply.assets,
                  let preview = WebPreviewSnapshot(textFiles: assets, preferredEntry: entry) else {
                throw BrowserBuildError(message: "The compiled preview exceeds 256 assets, 2 MiB per asset or 8 MiB in total.")
            }
            var additions: [String: String] = [:]
            if preparePackages {
                for path in reply.usedPaths ?? [] where path.split(separator: "/").contains("node_modules") {
                    if let source = files[path] { additions[path] = source }
                }
                // Preserve pins for already prepared, unchanged source packages.
                if let old = initial[lockPath],
                   let lock = try? JSONDecoder().decode(BrowserWebLock.self, from: Data(old.utf8)),
                   lock.manifest == initial[manifestPath] {
                    for (path, pin) in lock.packages where pins[path] == nil { pins[path] = pin }
                }
                let roots = Set(reply.packageRoots ?? [])
                pins = pins.filter { roots.contains($0.key) }
                let lock = BrowserWebLock(schemaVersion: 1, manifest: initial[manifestPath] ?? "{}", packages: pins)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                additions[lockPath] = String(decoding: try encoder.encode(lock), as: UTF8.self) + "\n"
                let retained = initial.filter { !$0.key.hasPrefix(sourceRemovalPrefix) && $0.key != lockPath }
                let merged = retained.merging(additions) { _, new in new }
                guard merged.count <= LocalProjectLoader.maximumFileCount,
                      merged.values.allSatisfy({ $0.utf8.count <= LocalProjectLoader.maximumFileBytes }),
                      merged.values.reduce(0, { $0 + $1.utf8.count }) <= LocalProjectLoader.maximumProjectBytes else {
                    throw BrowserBuildError(message: "Prepared browser source exceeds the editable project's 2,048-file, 2 MiB-per-file or 16 MB budget.")
                }
            }
            onStage("Browser bundle ready · \(reply.moduleCount ?? 0) modules · \(reply.packageRoots?.count ?? 0) npm packages")
            let rows = states.keys.sorted().map { id in
                let paths = packageIDs.keys.filter { packageIDs[$0] == id }
                let dependencies = Set(paths.flatMap { reply.packageDependencies?[$0] ?? [] }.compactMap { packageIDs[$0] }).sorted()
                return PackageTransferRow(package: id, dependencies: dependencies, state: states[id] ?? .ready)
            }
            return PreparedBrowserProject(preview: preview, sourceAdditions: additions,
                packageCount: reply.packageRoots?.count ?? 0, moduleCount: reply.moduleCount ?? 0, transfers: rows, sourceRemovalPrefix: sourceRemovalPrefix)
        }
        throw BrowserBuildError(message: "This browser dependency graph exceeds 2,048 package resolutions.")
    }
}

private struct BrowserWebLock: Codable {
    let schemaVersion: Int
    let manifest: String
    let packages: [String: BrowserPackagePin]
}


enum BrowserProjectCommand {
    case install(frozen: Bool, directory: String)
    case build(run: Bool, directory: String)
}

enum BrowserProjectConfiguration {
    static func isBrowserEntry(_ path: String) -> Bool {
        SourceLanguage(filePath: path) == .html || (path as NSString).lastPathComponent == "package.json"
    }

    static func manifestPath(files: [String: String], entry: String) -> String {
        var directory = (entry as NSString).deletingLastPathComponent
        while true {
            let candidate = directory.isEmpty ? "package.json" : directory + "/package.json"
            if files[candidate] != nil { return candidate }
            if directory.isEmpty { return "package.json" }
            directory = (directory as NSString).deletingLastPathComponent
        }
    }

    static func entry(files: [String: String], preferred: String, directory: String? = nil) -> String {
        let reference = directory.map { $0.isEmpty ? "package.json" : $0 + "/package.json" } ?? preferred
        let manifest = manifestPath(files: files, entry: reference)
        let root = (manifest as NSString).deletingLastPathComponent
        let prefix = root.isEmpty ? "" : root + "/"
        if SourceLanguage(filePath: preferred) == .html, files[preferred] != nil,
           directory == nil || preferred.hasPrefix(prefix) { return preferred }
        if files[prefix + "index.html"] != nil { return prefix + "index.html" }
        return files.keys.filter { $0.hasPrefix(prefix) && !$0.contains("node_modules/") && SourceLanguage(filePath: $0) == .html }
            .sorted { a, b in
                let ac = a.split(separator: "/").count, bc = b.split(separator: "/").count
                return ac == bc ? a < b : ac < bc
            }.first ?? manifest
    }
}
