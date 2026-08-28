import Foundation
import Compression

/// Limits every `.crate` archive is checked against before anything is written.
///
/// A `.crate` is a gzipped tar downloaded from the internet, so it gets the same
/// treatment Crabrix already gives GitHub snapshots: bounded, traversal-free,
/// and symlink-free.
struct CrateArchiveLimits: Sendable {
    var maximumCompressedBytes = 48 * 1024 * 1024
    var maximumExpandedBytes = 256 * 1024 * 1024
    var maximumEntries = 20_000
    var maximumPathComponents = 32
    var maximumFileBytes = 64 * 1024 * 1024

    static let `default` = CrateArchiveLimits()
}

enum CrateArchiveError: LocalizedError, Equatable {
    case notGzip
    case corruptArchive(String)
    case checksumMismatch(expected: String, actual: String)
    case archiveTooLarge
    case tooManyEntries
    case unsafePath(String)
    case unsupportedEntry(String)

    var errorDescription: String? {
        switch self {
        case .notGzip:
            "The downloaded package is not a gzip archive."
        case let .corruptArchive(detail):
            "The package archive is corrupt: \(detail)"
        case let .checksumMismatch(expected, actual):
            "Package checksum mismatch. Expected \(expected.prefix(12))…, got \(actual.prefix(12))…"
        case .archiveTooLarge:
            "The package archive is larger than Crabrix extracts."
        case .tooManyEntries:
            "The package archive contains more files than Crabrix extracts."
        case let .unsafePath(path):
            "The package archive contains an unsafe path: \(path)"
        case let .unsupportedEntry(path):
            "The package archive contains an unsupported entry: \(path)"
        }
    }
}

/// Minimal gzip reader built on the system `Compression` framework.
///
/// `COMPRESSION_ZLIB` decodes raw DEFLATE, so the gzip envelope is parsed here
/// and its CRC-32/ISIZE trailer is verified against the inflated bytes.
enum GzipDecoder {
    static func decompress(_ data: Data, limit: Int) throws -> Data {
        guard data.count > 18 else { throw CrateArchiveError.notGzip }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x1f, bytes[1] == 0x8b else { throw CrateArchiveError.notGzip }
        guard bytes[2] == 8 else {
            throw CrateArchiveError.corruptArchive("unsupported compression method")
        }

        let flags = bytes[3]
        var cursor = 10
        func require(_ count: Int) throws {
            guard cursor + count <= bytes.count else {
                throw CrateArchiveError.corruptArchive("truncated gzip header")
            }
        }

        if flags & 0x04 != 0 { // FEXTRA
            try require(2)
            let length = Int(bytes[cursor]) | Int(bytes[cursor + 1]) << 8
            cursor += 2
            try require(length)
            cursor += length
        }
        for flag in [UInt8(0x08), UInt8(0x10)] where flags & flag != 0 { // FNAME, FCOMMENT
            while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
            guard cursor < bytes.count else {
                throw CrateArchiveError.corruptArchive("truncated gzip header")
            }
            cursor += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            try require(2)
            cursor += 2
        }

        let trailerStart = bytes.count - 8
        guard cursor < trailerStart else {
            throw CrateArchiveError.corruptArchive("empty deflate stream")
        }
        let deflated = data.subdata(in: cursor..<trailerStart)
        let inflated = try inflate(deflated, limit: limit)

        let expectedCRC = UInt32(bytes[trailerStart])
            | UInt32(bytes[trailerStart + 1]) << 8
            | UInt32(bytes[trailerStart + 2]) << 16
            | UInt32(bytes[trailerStart + 3]) << 24
        let expectedSize = UInt32(bytes[trailerStart + 4])
            | UInt32(bytes[trailerStart + 5]) << 8
            | UInt32(bytes[trailerStart + 6]) << 16
            | UInt32(bytes[trailerStart + 7]) << 24

        guard UInt32(truncatingIfNeeded: inflated.count) == expectedSize else {
            throw CrateArchiveError.corruptArchive("gzip length mismatch")
        }
        guard CRC32.checksum(inflated) == expectedCRC else {
            throw CrateArchiveError.corruptArchive("gzip CRC mismatch")
        }
        return inflated
    }

    private static func inflate(_ data: Data, limit: Int) throws -> Data {
        var output = Data()
        let bufferSize = 256 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        var stream = compression_stream(
            dst_ptr: destination,
            dst_size: bufferSize,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK
        else {
            throw CrateArchiveError.corruptArchive("could not start the decompressor")
        }
        defer { compression_stream_destroy(&stream) }

        var thrown: (any Error)?
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let source = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.src_ptr = source
            stream.src_size = raw.count
            stream.dst_ptr = destination
            stream.dst_size = bufferSize

            while true {
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                if produced > 0 {
                    output.append(destination, count: produced)
                    stream.dst_ptr = destination
                    stream.dst_size = bufferSize
                }
                if output.count > limit {
                    thrown = CrateArchiveError.archiveTooLarge
                    return
                }
                switch status {
                case COMPRESSION_STATUS_END:
                    return
                case COMPRESSION_STATUS_OK:
                    continue
                default:
                    thrown = CrateArchiveError.corruptArchive("deflate stream error")
                    return
                }
            }
        }
        if let thrown { throw thrown }
        return output
    }
}

enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { raw in
            for byte in raw.bindMemory(to: UInt8.self) {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

/// One regular file taken out of a `.crate` tarball.
struct CrateArchiveFile: Sendable {
    /// Path with the crate's `name-version/` prefix removed.
    let path: String
    let contents: Data
}

/// A ustar/GNU tar reader that only ever yields regular files.
enum TarArchiveReader {
    static func entries(
        in data: Data,
        limits: CrateArchiveLimits = .default
    ) throws -> [CrateArchiveFile] {
        var files: [CrateArchiveFile] = []
        var offset = 0
        var totalBytes = 0
        /// GNU long-name records set the path used by the following entry.
        var pendingLongName: String?

        while offset + 512 <= data.count {
            let header = data.subdata(in: offset..<(offset + 512))
            offset += 512
            if header.allSatisfy({ $0 == 0 }) { break }

            guard let rawName = string(in: header, at: 0, length: 100) else {
                throw CrateArchiveError.corruptArchive("unreadable entry name")
            }
            guard let sizeField = string(in: header, at: 124, length: 12),
                  let size = octal(sizeField)
            else {
                throw CrateArchiveError.corruptArchive("unreadable entry size")
            }
            let typeFlag = header[header.startIndex + 156]
            let prefix = string(in: header, at: 345, length: 155) ?? ""

            let padded = (size + 511) / 512 * 512
            guard offset + size <= data.count else {
                throw CrateArchiveError.corruptArchive("truncated entry body")
            }
            let body = data.subdata(in: offset..<(offset + size))
            offset += padded

            // GNU long name / long link records carry the next entry's path.
            if typeFlag == UInt8(ascii: "L") {
                pendingLongName = String(decoding: body, as: UTF8.self)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                continue
            }
            if typeFlag == UInt8(ascii: "K") { continue }
            // Directories and PAX metadata carry nothing Crabrix needs.
            if typeFlag == UInt8(ascii: "5")
                || typeFlag == UInt8(ascii: "x")
                || typeFlag == UInt8(ascii: "g") {
                pendingLongName = nil
                continue
            }

            let name = pendingLongName
                ?? (prefix.isEmpty ? rawName : "\(prefix)/\(rawName)")
            pendingLongName = nil

            // Anything that is not a plain file could point outside the sandbox.
            guard typeFlag == 0 || typeFlag == UInt8(ascii: "0") else {
                throw CrateArchiveError.unsupportedEntry(name)
            }
            guard size <= limits.maximumFileBytes else {
                throw CrateArchiveError.archiveTooLarge
            }

            totalBytes += size
            guard totalBytes <= limits.maximumExpandedBytes else {
                throw CrateArchiveError.archiveTooLarge
            }
            files.append(CrateArchiveFile(path: name, contents: body))
            guard files.count <= limits.maximumEntries else {
                throw CrateArchiveError.tooManyEntries
            }
        }
        return files
    }

    /// Reads a NUL-padded ASCII header field.
    private static func string(in header: Data, at offset: Int, length: Int) -> String? {
        let start = header.startIndex + offset
        guard start + length <= header.endIndex else { return nil }
        var bytes = [UInt8](header[start..<(start + length)])
        if let terminator = bytes.firstIndex(of: 0) { bytes = Array(bytes[..<terminator]) }
        return String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Tar sizes are octal text, except for GNU's base-256 form for large files.
    private static func octal(_ field: String) -> Int? {
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        guard let value = Int(trimmed, radix: 8), value >= 0 else { return nil }
        return value
    }

    /// Strips the mandatory `name-version/` root and rejects unsafe paths.
    static func normalizedRelativePath(
        _ path: String,
        strippingRoot root: String,
        limits: CrateArchiveLimits = .default
    ) throws -> String? {
        var value = path
        if value.hasPrefix("./") { value.removeFirst(2) }
        guard !value.hasPrefix("/"), !value.contains("\0") else {
            throw CrateArchiveError.unsafePath(path)
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return nil }
        guard !components.contains(where: { $0 == ".." || $0 == "." }) else {
            throw CrateArchiveError.unsafePath(path)
        }
        guard components.count <= limits.maximumPathComponents else {
            throw CrateArchiveError.unsafePath(path)
        }
        guard components[0] == root else {
            // A `.crate` that does not use its own `name-version` root is not the
            // archive Cargo published.
            throw CrateArchiveError.unsafePath(path)
        }
        let remainder = components.dropFirst()
        guard !remainder.isEmpty else { return nil }
        return remainder.joined(separator: "/")
    }
}
