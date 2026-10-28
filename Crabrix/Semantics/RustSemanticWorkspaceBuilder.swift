import Foundation

enum RustSemanticWorkspaceBuilder {
    static func build(_ context: RustSemanticContext, sourceRoot: URL? = CrateStorageLayout.sourceDirectory) throws -> RustSemanticWorkspace {
        let project = context.project
        guard project.entryFile.hasSuffix(".rs"), project.files[project.entryFile] != nil,
              context.plan.units.count <= 252 else {
            throw RustSemanticError.unavailable("Select a Rust entry within the bounded semantic profile. Compiler Check remains available.")
        }
        var files = project.files.filter { $0.key.hasSuffix(".rs") }
        guard !files.keys.contains(where: { $0.hasPrefix("__lib/") || $0.hasPrefix("__dep/") }) else {
            throw RustSemanticError.unavailable("This project uses a reserved analysis path. Its source is kept unchanged.")
        }
        var roots: [String: String] = [:]
        for unit in context.plan.units {
            guard !unit.isProceduralMacro, unit.buildScriptPath == nil else {
                throw RustSemanticError.unavailable("External procedural macros and build-script-generated files are outside this semantic profile. Compiler Check remains separate.")
            }
            roots[unit.fingerprint] = "__dep/\(unit.fingerprint)/\(unit.libraryPath)"
        }
        func dependencies(_ externs: [CargoExtern]) throws -> [String: String] {
            var result: [String: String] = [:]
            for item in externs {
                guard let root = roots[item.fingerprint], !item.isProceduralMacro else {
                    throw RustSemanticError.unavailable("The prepared dependency graph is incomplete for analysis.")
                }
                result[item.alias] = root
            }
            return result
        }
        let rootName = CratePackageManifest.crateIdentifier(for: ((project.entryFile as NSString).lastPathComponent as NSString).deletingPathExtension)
        var crates = [RustSemanticWorkspace.Crate(root: project.entryFile, dependencies: try dependencies(context.plan.rootExterns),
                                                edition: context.edition, kind: "", name: rootName, features: context.plan.rootFeatures)]
        var total = files.values.reduce(0) { $0 + $1.utf8.count }
        guard files.values.allSatisfy({ $0.utf8.count <= 1024 * 1024 }) else {
            throw RustSemanticError.unavailable("A project file exceeds the 1 MiB analysis profile. Compiler Check remains available.")
        }
        try validate(files, bytes: total)
        for unit in context.plan.units {
            try Task.checkCancellation()
            guard let sourceRoot else { throw RustSemanticError.unavailable("Prepared dependency source is unavailable offline.") }
            let directory: String
            let overlay: String?
            switch unit.source {
            case let .registry(name): directory = name; overlay = nil
            case let .projectPatch(relative, registry): directory = registry; overlay = relative
            }
            guard !directory.isEmpty, directory != ".", directory != "..", !directory.contains("/"), !directory.contains("\\") else {
                throw RustSemanticError.unavailable("Invalid prepared dependency path.")
            }
            let root = sourceRoot.appending(path: directory)
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
            guard (try root.resourceValues(forKeys: keys)).isSymbolicLink != true,
                  let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else {
                throw RustSemanticError.unavailable("Prepared dependency source is unavailable. Prepare packages before requesting analysis.")
            }
            var visited = 0, dependency: [String: String] = [:], dependencyBytes = 0
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                visited += 1
                guard visited <= 20_000 else { throw RustSemanticError.unavailable("Dependency analysis exceeds its file budget.") }
                let values = try url.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true else { throw RustSemanticError.unavailable("Symbolic-link dependencies are outside the analysis profile.") }
                guard values.isRegularFile == true, url.pathExtension == "rs" else { continue }
                let relative = String(url.path.dropFirst(root.path.count + 1))
                try ProjectFilePolicy.validatePath(relative)
                guard let size = values.fileSize, size >= 0, size <= 1024 * 1024 else { throw RustSemanticError.unavailable("A dependency source file exceeds the analysis budget.") }
                // Reject the advertised size before allocating the next source.
                // A crate may contain thousands of files even when each is small.
                try validate(count: files.count + dependency.count + 1, bytes: total + dependencyBytes + size)
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
                guard data.count <= 1024 * 1024, let source = String(data: data, encoding: .utf8) else {
                    throw RustSemanticError.unavailable("A dependency source file is not bounded UTF-8 text.")
                }
                try validate(count: files.count + dependency.count + 1, bytes: total + dependencyBytes + data.count)
                dependency[relative] = source
                dependencyBytes += data.count
            }
            if let overlay {
                try ProjectFilePolicy.validatePath(overlay)
                for (path, text) in project.files where path.hasPrefix(overlay + "/") && path.hasSuffix(".rs") {
                    let relative = String(path.dropFirst(overlay.count + 1))
                    dependencyBytes += text.utf8.count - (dependency[relative]?.utf8.count ?? 0)
                    let count = dependency.count + (dependency[relative] == nil ? 1 : 0)
                    try validate(count: files.count + count, bytes: total + dependencyBytes)
                    dependency[relative] = text
                }
            }
            guard dependency[unit.libraryPath] != nil else { throw RustSemanticError.unavailable("The prepared library entry is missing from analysis source.") }
            for (relative, text) in dependency {
                guard text.utf8.count <= 1024 * 1024 else { throw RustSemanticError.unavailable("A dependency overlay exceeds the analysis file budget.") }
                let path = "__dep/\(unit.fingerprint)/\(relative)"
                files[path] = text; total += text.utf8.count
                try validate(files, bytes: total)
            }
            crates.append(.init(root: roots[unit.fingerprint]!, dependencies: try dependencies(unit.externs),
                                edition: unit.edition, kind: "library", name: unit.crateName, features: unit.features))
        }
        return RustSemanticWorkspace(files: files.keys.sorted().map { .init(path: $0, text: files[$0]!) }, crates: crates)
    }

    private static func validate(_ files: [String: String], bytes: Int) throws {
        try validate(count: files.count, bytes: bytes)
    }

    private static func validate(count: Int, bytes: Int) throws {
        guard count <= 2048, bytes <= 8 * 1024 * 1024 else {
            throw RustSemanticError.unavailable("Semantic analysis supports 2,048 Rust files, 1 MiB per file and 8 MiB of project/dependency source. Editing and compiler Check retain their separate limits.")
        }
    }
}
