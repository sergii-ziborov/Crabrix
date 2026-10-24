import Foundation

/// The deliberately small Cargo protocol supported by the offline WASI host.
/// Arguments remain individual argv entries; no shell or host process is used.
struct CargoBuildScriptOutput: Equatable {
    var compilerArguments: [String] = []
    var environment: [String: String] = [:]

    static func parse(_ stdout: String) throws -> Self {
        var result = Self()
        for line in stdout.split(whereSeparator: \.isNewline) {
            let instruction: Substring
            if line.hasPrefix("cargo::") { instruction = line.dropFirst(7) }
            else if line.hasPrefix("cargo:") { instruction = line.dropFirst(6) }
            else { continue }
            let pair = instruction.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { throw Failure("Malformed build-script instruction: \(line)") }
            let key = String(pair[0]), value = String(pair[1])
            switch key {
            case "rustc-cfg": result.compilerArguments += ["--cfg", value]
            case "rustc-check-cfg": result.compilerArguments += ["--check-cfg", value]
            case "rustc-env":
                let assignment = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard assignment.count == 2, !assignment[0].isEmpty,
                      assignment[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                      !assignment[0].hasPrefix("CARGO_"),
                      !["OUT_DIR", "CLIF2WASM_OBJECT", "RUSTC", "RUSTFLAGS", "HOST", "TARGET"]
                        .contains(String(assignment[0]))
                else { throw Failure("Unsupported build-script environment assignment: \(value)") }
                result.environment[String(assignment[0])] = String(assignment[1])
            case "error": throw Failure(value)
            // All package files and the controlled environment are already
            // covered by the unit fingerprint. No ambient host environment is exposed.
            case "rerun-if-changed", "rerun-if-env-changed", "warning": break
            default:
                throw Failure("Build-script instruction \(key) is not supported by the offline WASI host.")
            }
        }
        return result
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
