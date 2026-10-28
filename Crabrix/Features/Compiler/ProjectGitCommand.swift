import Foundation

enum ProjectGitCommand: Equatable {
    case initialize, status, log, branches
    case fetch, pull, push, remote
    case clone(String), connectRemote(String)
    case diff(String), branch(String), checkout(String)
    case commit(message: String, paths: [String])
    case show(commit: String, path: String), restore(commit: String, path: String)
    case identity(key: String, value: String?)

    static func parse(_ arguments: [String]) throws -> Self {
        if arguments == ["init"] { return .initialize }
        if arguments == ["status"] { return .status }
        if arguments == ["log"] { return .log }
        if arguments == ["branch"] { return .branches }
        if arguments == ["fetch"] || arguments == ["fetch", "origin"] { return .fetch }
        if arguments == ["pull"] || arguments == ["pull", "--ff-only"] { return .pull }
        if arguments == ["push"] || arguments == ["push", "origin"] { return .push }
        if arguments == ["remote", "-v"] { return .remote }
        if arguments.count == 4, Array(arguments.prefix(3)) == ["remote", "add", "origin"] { return .connectRemote(arguments[3]) }
        if arguments.count == 2, !arguments[1].hasPrefix("-") {
            switch arguments[0] {
            case "diff": return .diff(arguments[1])
            case "branch": return .branch(arguments[1])
            case "switch": return .checkout(arguments[1])
            case "clone": return .clone(arguments[1])
            case "show":
                let parts = arguments[1].split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 { return .show(commit: parts[0], path: parts[1]) }
            default: break
            }
        }
        if arguments.count >= 5, arguments[0] == "commit", arguments[1] == "-m", arguments[3] == "--" {
            return .commit(message: arguments[2], paths: Array(arguments.dropFirst(4)))
        }
        if arguments.count == 5, arguments[0] == "restore", arguments[1] == "--source", arguments[3] == "--" {
            return .restore(commit: arguments[2], path: arguments[4])
        }
        if [2, 3].contains(arguments.count), arguments[0] == "config", ["user.name", "user.email"].contains(arguments[1]) {
            return .identity(key: arguments[1], value: arguments.count == 3 ? arguments[2] : nil)
        }
        throw GitCommandFailure()
    }
}

private struct GitCommandFailure: LocalizedError {
    var errorDescription: String? {
        "Git profile: git init · status · diff <path> · log · branch [name] · switch <name> · commit -m \"message\" -- <paths> · show <full-commit>:<path> · restore --source <full-commit> -- <path>. HTTPS GitHub: clone <url> · remote add origin <url> · remote -v · fetch · pull --ff-only · push. git config user.name/user.email sets this device's commit identity. Save private access in Git settings, never in a command. Restore opens a preview. Refresh with git status before mutations. Independent staging, force push, merge/rebase and extra options are not enabled."
    }
}
