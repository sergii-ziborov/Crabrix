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
        var section = ""
        var packageName: String?
        var packageVersion: String?
        var packageEdition: String?
        var dependencies: [Dependency] = []

        for rawLine in source.split(whereSeparator: \.isNewline) {
            let line = stripComment(from: String(rawLine)).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }

            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = unquote(String(line[..<separator]).trimmingCharacters(in: .whitespaces))
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)

            switch section {
            case "package":
                switch key {
                case "name": packageName = quotedValue(value)
                case "version": packageVersion = quotedValue(value)
                case "edition": packageEdition = quotedValue(value)
                default: break
                }
            case "dependencies":
                dependencies.append(parseDependency(name: key, value: value))
            default:
                continue
            }
        }

        guard let packageName, !packageName.isEmpty else { return nil }
        return CargoManifest(
            name: packageName,
            version: packageVersion,
            edition: packageEdition,
            dependencies: dependencies.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        )
    }

    private static func parseDependency(name: String, value: String) -> Dependency {
        if let requirement = quotedValue(value) {
            return Dependency(name: name, requirement: requirement, source: .registry)
        }

        guard value.hasPrefix("{"), value.hasSuffix("}") else {
            return Dependency(name: name, requirement: nil, source: .unknown)
        }

        let source: Dependency.Source
        if inlineValue(named: "path", in: value) != nil {
            source = .path
        } else if inlineValue(named: "git", in: value) != nil {
            source = .git
        } else if inlineValue(named: "version", in: value) != nil {
            source = .registry
        } else {
            source = .unknown
        }
        return Dependency(
            name: name,
            requirement: inlineValue(named: "version", in: value),
            source: source
        )
    }

    private static func inlineValue(named name: String, in value: String) -> String? {
        for component in value.dropFirst().dropLast().split(separator: ",") {
            let pair = component.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            guard pair.count == 2, unquote(pair[0]) == name else { continue }
            return quotedValue(pair[1])
        }
        return nil
    }

    private static func quotedValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2,
              let first = trimmed.first,
              let last = trimmed.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else {
            return nil
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func unquote(_ value: String) -> String {
        quotedValue(value) ?? value
    }

    private static func stripComment(from line: String) -> String {
        var quote: Character?
        for index in line.indices {
            let character = line[index]
            if character == "\"" || character == "'" {
                quote = quote == character ? nil : (quote ?? character)
            } else if character == "#", quote == nil {
                return String(line[..<index])
            }
        }
        return line
    }
}
