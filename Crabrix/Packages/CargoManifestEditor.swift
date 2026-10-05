import Foundation

enum CargoManifestEditor {
    /// These libraries expose useful parsing/token APIs on WASI without the
    /// host-only proc_macro crate. Write the choice into Cargo.toml so the
    /// dependency graph remains explicit and reproducible.
    static func localCompilerDeclaration(name: String, requirement: String) -> String {
        switch name {
        case "syn":
            return "syn = { version = \"\(requirement)\", default-features = false, features = [\"derive\", \"parsing\", \"printing\", \"clone-impls\"] }"
        case "quote", "proc-macro2":
            return "\(name) = { version = \"\(requirement)\", default-features = false }"
        default:
            return "\(name) = \"\(requirement)\""
        }
    }

    static func hasLocalCompilerProfile(name: String) -> Bool {
        name == "syn" || name == "quote" || name == "proc-macro2"
    }

    /// Repairs a pre-existing plain `syn = "…"` entry without rewriting the
    /// rest of the user's manifest. Explicit feature selections are preserved.
    static func usingSynParserFeatures(_ source: String) throws -> String {
        let manifest = try CratePackageManifest.parse(source)
        guard let dependency = manifest.dependencies.first(where: {
            $0.kind == .normal && $0.alias == "syn" && $0.packageName == "syn"
                && $0.isRegistry && !$0.isOptional && $0.usesDefaultFeatures
                && $0.features.isEmpty
        }), let requirement = dependency.requirementText,
              !requirement.contains("\"")
        else { return source }

        guard let statement = try TOMLParser.statements(in: source).first(where: {
            $0.path == ["dependencies", "syn"] && $0.valueRange != nil
        }), let range = statement.valueRange else { return source }
        var characters = Array(source)
        let declaration = localCompilerDeclaration(name: "syn", requirement: requirement)
        guard let value = declaration.split(separator: "=", maxSplits: 1).last?
            .trimmingCharacters(in: .whitespaces) else { return source }
        characters.replaceSubrange(range, with: value)
        let updated = String(characters)
        _ = try CratePackageManifest.parse(updated)
        return updated
    }

    /// Removes a direct dependency by its Cargo alias, without rewriting the
    /// rest of the manifest or deleting cached sources shared by other projects.
    static func removingDependency(_ alias: String, from source: String) throws -> String {
        let statements = try TOMLParser.statements(in: source)
        let document = try TOMLParser.parse(source)
        let hasNamedFeature = document["features"]?[alias] != nil
        var edits: [(Range<Int>, String)] = []

        for statement in statements {
            let path = statement.path
            let dependencyPrefix: [String]?
            if path.first == "dependencies" {
                dependencyPrefix = ["dependencies", alias]
            } else if path.count >= 3, path[0] == "target", path[2] == "dependencies" {
                dependencyPrefix = Array(path.prefix(3)) + [alias]
            } else {
                dependencyPrefix = nil
            }
            if let prefix = dependencyPrefix, path.starts(with: prefix) {
                edits.append((statement.range, ""))
            } else if path.count == 2, path[0] == "features",
                      let values = statement.value?.stringArrayValue,
                      let range = statement.valueRange {
                let kept = values.filter { value in
                    value != "dep:\(alias)"
                        && !value.hasPrefix("\(alias)/")
                        && !value.hasPrefix("\(alias)?/")
                        && (value != alias || hasNamedFeature)
                }
                if kept != values {
                    // JSON string arrays use escapes that are also valid TOML.
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.withoutEscapingSlashes]
                    let data = try encoder.encode(kept)
                    edits.append((range, String(decoding: data, as: UTF8.self)))
                }
            }
        }

        var characters = Array(source)
        for (range, replacement) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            characters.replaceSubrange(range, with: replacement)
        }
        let updated = String(characters)
        _ = try TOMLParser.parse(updated)
        return updated
    }
}
