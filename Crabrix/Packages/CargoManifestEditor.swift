import Foundation

enum CargoManifestEditor {
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
