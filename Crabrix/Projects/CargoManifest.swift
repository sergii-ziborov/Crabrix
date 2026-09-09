import Foundation

struct CargoManifest: Equatable, Sendable {
    struct Dependency: Equatable, Sendable, Identifiable {
        enum Source: String, Sendable {
            case registry
            case path
            case git
            case unknown
        }

        let name: String
        let requirement: String?
        let source: Source

        var id: String { name }
    }

    let name: String
    let version: String?
    let edition: String?
    let dependencies: [Dependency]

    static func parse(_ source: String) -> CargoManifest? {
        guard let document = try? TOMLParser.parse(source),
              let package = document["package"]?.tableValue,
              let name = package["name"]?.stringValue, !name.isEmpty
        else { return nil }

        // Use the same TOML reader as resolution so table-form dependencies
        // and aliases remain manageable even when package preparation fails.
        var declarations = document["dependencies"]?.tableValue ?? [:]
        for target in document["target"]?.tableValue?.values ?? [:].values {
            declarations.merge(target["dependencies"]?.tableValue ?? [:]) { existing, _ in existing }
        }
        let dependencies = declarations.map { name, value in
            let source: Dependency.Source
            if value["path"] != nil { source = .path }
            else if value["git"] != nil { source = .git }
            else if value.stringValue != nil || value["version"] != nil { source = .registry }
            else { source = .unknown }
            return Dependency(
                name: name,
                requirement: value.stringValue ?? value["version"]?.stringValue,
                source: source
            )
        }
        return CargoManifest(
            name: name,
            version: package["version"]?.stringValue,
            edition: package["edition"]?.stringValue,
            dependencies: dependencies.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        )
    }
}
