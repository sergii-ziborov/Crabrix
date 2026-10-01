import Foundation

/// The signed app bundle carries one release input for compiler identity.
/// A missing or malformed resource makes the compiler unavailable instead of
/// allowing a stale cache identity to stand in for a different binary.
struct AppToolchainRelease: Decodable, Sendable {
    struct RustVersionComponents: Decodable, Sendable {
        let major: Int
        let minor: Int
        let patch: Int
    }

    let schemaVersion: Int
    let toolchainID: String
    let target: String
    let rustVersion: String
    let rustVersionComponents: RustVersionComponents
    let rustcSHA256: String
    let sysrootManifestSHA256: String
    let sysrootArchiveSHA256: String

    static func load(in bundle: Bundle = .main) -> AppToolchainRelease? {
        guard let url = bundle.url(forResource: "toolchain.lock", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let release = try? JSONDecoder().decode(Self.self, from: data),
              release.schemaVersion == 1, release.target == "wasm32-wasip1",
              release.toolchainID.range(
                of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression
              ) != nil,
              release.rustVersion == release.versionBase
                || release.rustVersion.hasPrefix(release.versionBase + "-"),
              [release.rustcSHA256, release.sysrootManifestSHA256,
               release.sysrootArchiveSHA256].allSatisfy({ digest in
                  digest.count == 64 && digest.allSatisfy { "0123456789abcdef".contains($0) }
              })
        else { return nil }
        return release
    }

    private var versionBase: String {
        "\(rustVersionComponents.major).\(rustVersionComponents.minor).\(rustVersionComponents.patch)"
    }
}
