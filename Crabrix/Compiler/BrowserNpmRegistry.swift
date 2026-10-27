import CryptoKit
import Foundation

/// Downloads data from the public npm registry only. No lifecycle scripts,
/// plugins, host executables or downloaded native libraries are executed.
actor BrowserNpmRegistry {
    struct Version: Decodable, Sendable {
        struct Dist: Decodable, Sendable {
            let tarball: String
            let integrity: String?
            let shasum: String?
        }
        let name: String
        let version: String
        let dist: Dist
    }
    struct Source: Sendable {
        let files: [String: String]
        let cached: Bool
        let integrity: String
    }
    private struct Metadata: Decodable { let versions: [String: Version] }
    private var metadata: [String: [String: Version]] = [:]
    private let cacheDirectory: URL
    private let session: URLSession
    private let redirectGuard = BrowserRegistryRedirectGuard()

    init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "Crabrix/BrowserPackageArchives", directoryHint: .isDirectory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration, delegate: redirectGuard, delegateQueue: nil)
    }

    nonisolated static func permitted(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "registry.npmjs.org"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }

    func versions(for name: String) async throws -> [String: Version] {
        if let cached = metadata[name] { return cached }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._-")
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://registry.npmjs.org/" + encoded), Self.permitted(url) else {
            throw BrowserBuildError(message: "Invalid public npm package name.")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.npm.install-v1+json", forHTTPHeaderField: "Accept")
        let data = try await download(request, maximum: 16 * 1024 * 1024)
        let result = try JSONDecoder().decode(Metadata.self, from: data).versions
        guard !result.isEmpty, result.count <= 30_000 else {
            throw BrowserBuildError(message: "The npm registry returned an unsupported version catalog for \(name).")
        }
        if metadata.count >= 32 { metadata.removeAll() }
        metadata[name] = result
        return result
    }

    func source(for package: Version, onState: @escaping @Sendable (PackageTransferRow.State) -> Void) async throws -> Source {
        guard let url = URL(string: package.dist.tarball), Self.permitted(url) else {
            throw BrowserBuildError(message: "The package archive must come from the public npm HTTPS registry.")
        }
        let integrity: String
        if let sri = package.dist.integrity { integrity = sri }
        else if let hex = package.dist.shasum, hex.count == 40,
                let bytes = Self.hexBytes(hex) { integrity = "sha1-" + bytes.base64EncodedString() }
        else { throw BrowserBuildError(message: "npm/\(package.name) has no verifiable archive integrity.") }
        let key = SHA256.hash(data: Data((url.absoluteString + "\n" + integrity).utf8)).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let archive = cacheDirectory.appending(path: key + ".tgz")
        var cached = false
        let data: Data
        if let local = try? Data(contentsOf: archive), Self.valid(local, integrity: integrity) {
            data = local; cached = true; onState(.cached)
        } else {
            onState(.downloading)
            data = try await download(URLRequest(url: url), maximum: 24 * 1024 * 1024)
            onState(.verifying)
            guard Self.valid(data, integrity: integrity) else {
                let reason = "npm/\(package.name) \(package.version) archive integrity failed."
                onState(.failed(reason)); throw BrowserBuildError(message: reason)
            }
            try data.write(to: archive, options: .atomic)
        }
        try Task.checkCancellation()
        var limits = CrateArchiveLimits()
        limits.maximumCompressedBytes = 24 * 1024 * 1024
        limits.maximumExpandedBytes = 64 * 1024 * 1024
        limits.maximumFileBytes = 4 * 1024 * 1024
        limits.maximumEntries = 12_000
        let expanded = try GzipDecoder.decompress(data, limit: limits.maximumExpandedBytes)
        var files: [String: String] = [:], names = Set<String>()
        for file in try TarArchiveReader.entries(in: expanded, limits: limits) {
            try Task.checkCancellation()
            guard let path = try TarArchiveReader.normalizedRelativePath(file.path, strippingRoot: "package", limits: limits),
                  WebPreviewSnapshot.isSafePath(path) else { continue }
            let folded = path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard names.insert(folded).inserted else { throw BrowserBuildError(message: "The npm archive has colliding source paths: \(path)") }
            let ext = (path as NSString).pathExtension.lowercased()
            let name = (path as NSString).lastPathComponent.uppercased()
            guard ["js","mjs","cjs","jsx","ts","tsx","json","css","svg","html","txt","md"].contains(ext)
                    || name.hasPrefix("LICENSE") || name.hasPrefix("LICENCE") || name == "COPYING" || name.hasPrefix("NOTICE") else { continue }
            if let text = String(data: file.contents, encoding: .utf8) { files[path] = text }
        }
        guard let manifest = files["package.json"],
              let object = try JSONSerialization.jsonObject(with: Data(manifest.utf8)) as? [String: Any],
              object["name"] as? String == package.name, object["version"] as? String == package.version else {
            throw BrowserBuildError(message: "The npm archive's package.json does not match \(package.name) \(package.version).")
        }
        onState(cached ? .cached : .ready)
        return Source(files: files, cached: cached, integrity: integrity)
    }

    private func download(_ request: URLRequest, maximum: Int) async throws -> Data {
        guard let url = request.url, Self.permitted(url) else { throw BrowserBuildError(message: "Unsupported npm download URL.") }
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let final = response.url, Self.permitted(final),
              response.expectedContentLength <= Int64(maximum) else {
            throw BrowserBuildError(message: "The npm registry request failed or exceeded the download limit.")
        }
        var data = Data(), buffer = [UInt8](); buffer.reserveCapacity(64 * 1024)
        for try await byte in stream {
            buffer.append(byte)
            if buffer.count == 64 * 1024 {
                try Task.checkCancellation()
                guard data.count + buffer.count <= maximum else { throw BrowserBuildError(message: "The npm registry response exceeded its byte limit.") }
                data.append(contentsOf: buffer); buffer.removeAll(keepingCapacity: true)
            }
        }
        guard data.count + buffer.count <= maximum else { throw BrowserBuildError(message: "The npm registry response exceeded its byte limit.") }
        data.append(contentsOf: buffer)
        return data
    }

    nonisolated static func valid(_ data: Data, integrity: String) -> Bool {
        // Prefer the strongest supported SRI token. npm's historical SHA-1
        // archives remain readable; new registry archives normally use SHA-512.
        let tokens = integrity.split(whereSeparator: \.isWhitespace).map(String.init)
        for algorithm in ["sha512", "sha384", "sha256", "sha1"] {
            let selected = tokens.filter { $0.hasPrefix(algorithm + "-") }
            if selected.isEmpty { continue }
            let actual: Data
            switch algorithm {
            case "sha512": actual = Data(SHA512.hash(data: data))
            case "sha384": actual = Data(SHA384.hash(data: data))
            case "sha256": actual = Data(SHA256.hash(data: data))
            default: actual = Data(Insecure.SHA1.hash(data: data))
            }
            return selected.contains { token in
                let value = token.dropFirst(algorithm.count + 1).split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
                return Data(base64Encoded: value) == actual
            }
        }
        return false
    }

    nonisolated private static func hexBytes(_ text: String) -> Data? {
        guard text.count % 2 == 0 else { return nil }
        var result = Data(); var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<end], radix: 16) else { return nil }
            result.append(byte); index = end
        }
        return result
    }
}

private final class BrowserRegistryRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(BrowserNpmRegistry.permitted) == true ? request : nil)
    }
}
