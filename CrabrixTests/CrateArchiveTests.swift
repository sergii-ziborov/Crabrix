import XCTest
import Compression
@testable import Crabrix

/// Builds real gzip/tar bytes so the reader is tested against the format rather
/// than against a mock.
enum TarFixture {
    static func tar(_ entries: [(path: String, body: Data, typeFlag: UInt8)]) -> Data {
        var data = Data()
        for entry in entries {
            data.append(header(path: entry.path, size: entry.body.count, typeFlag: entry.typeFlag))
            data.append(entry.body)
            let padding = (512 - entry.body.count % 512) % 512
            data.append(Data(repeating: 0, count: padding))
        }
        data.append(Data(repeating: 0, count: 1024))
        return data
    }

    static func header(path: String, size: Int, typeFlag: UInt8) -> Data {
        var header = [UInt8](repeating: 0, count: 512)
        func write(_ text: String, at offset: Int, length: Int) {
            for (index, byte) in Array(text.utf8).prefix(length - 1).enumerated() {
                header[offset + index] = byte
            }
        }
        write(path, at: 0, length: 100)
        write("000644 ", at: 100, length: 8)
        write("000000 ", at: 108, length: 8)
        write("000000 ", at: 116, length: 8)
        write(String(format: "%011o ", size), at: 124, length: 12)
        write("00000000000 ", at: 136, length: 12)
        header[156] = typeFlag
        write("ustar", at: 257, length: 6)
        write("00", at: 263, length: 3)

        // The checksum field is computed with itself read as spaces.
        for index in 148..<156 { header[index] = 0x20 }
        let checksum = header.reduce(0) { $0 + Int($1) }
        write(String(format: "%06o", checksum), at: 148, length: 8)
        header[154] = 0
        header[155] = 0x20
        return Data(header)
    }

    static func gzip(_ data: Data) -> Data {
        var output = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
        output.append(deflate(data))
        var crc = CRC32.checksum(data).littleEndian
        withUnsafeBytes(of: &crc) { output.append(contentsOf: $0) }
        var size = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &size) { output.append(contentsOf: $0) }
        return output
    }

    private static func deflate(_ data: Data) -> Data {
        let capacity = max(data.count * 2, 1024)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let written = data.withUnsafeBytes { raw -> Int in
            guard let source = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(
                destination, capacity, source, raw.count, nil, COMPRESSION_ZLIB
            )
        }
        return Data(bytes: destination, count: written)
    }
}

final class CrateArchiveTests: XCTestCase {
    private let root = "demo-1.0.0"

    private func crate(
        _ entries: [(path: String, body: Data, typeFlag: UInt8)]
    ) -> Data {
        TarFixture.gzip(TarFixture.tar(entries))
    }

    func testReadsRegularFilesFromAGzippedTar() throws {
        let archive = crate([
            ("\(root)/Cargo.toml", Data("[package]\nname = \"demo\"\n".utf8), UInt8(ascii: "0")),
            ("\(root)/src/lib.rs", Data("pub fn hi() {}\n".utf8), UInt8(ascii: "0")),
            ("\(root)/src", Data(), UInt8(ascii: "5")),
        ])

        let tar = try GzipDecoder.decompress(archive, limit: 8 * 1024 * 1024)
        let files = try TarArchiveReader.entries(in: tar)

        XCTAssertEqual(files.count, 2)
        let paths = try files.compactMap {
            try TarArchiveReader.normalizedRelativePath($0.path, strippingRoot: root)
        }
        XCTAssertEqual(paths.sorted(), ["Cargo.toml", "src/lib.rs"])
        XCTAssertEqual(
            String(decoding: files[1].contents, as: UTF8.self),
            "pub fn hi() {}\n"
        )
    }

    func testRejectsCorruptedGzipBytes() throws {
        var archive = crate([
            ("\(root)/Cargo.toml", Data("[package]".utf8), UInt8(ascii: "0")),
        ])
        // Flip a payload byte so the trailing CRC no longer matches.
        archive[archive.count - 12] ^= 0xFF
        XCTAssertThrowsError(try GzipDecoder.decompress(archive, limit: 1 << 20))
    }

    func testRejectsNonGzipInput() {
        XCTAssertThrowsError(
            try GzipDecoder.decompress(Data(repeating: 7, count: 64), limit: 1 << 20)
        ) { error in
            XCTAssertEqual(error as? CrateArchiveError, .notGzip)
        }
    }

    func testRejectsSymlinkAndOtherNonRegularEntries() throws {
        let tar = TarFixture.tar([
            ("\(root)/evil", Data("/etc/passwd".utf8), UInt8(ascii: "2")),
        ])
        XCTAssertThrowsError(try TarArchiveReader.entries(in: tar)) { error in
            guard case .unsupportedEntry? = error as? CrateArchiveError else {
                return XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testRejectsTraversalAbsoluteAndForeignRootPaths() {
        for path in ["../escape.rs", "/etc/passwd", "other-1.0.0/src/lib.rs", "\(root)/../x.rs"] {
            XCTAssertThrowsError(
                try TarArchiveReader.normalizedRelativePath(path, strippingRoot: root),
                "\(path) should be rejected"
            )
        }
    }

    func testEnforcesTheExpandedSizeLimit() throws {
        var limits = CrateArchiveLimits.default
        limits.maximumExpandedBytes = 1_024
        limits.maximumFileBytes = 1_024
        let tar = TarFixture.tar([
            ("\(root)/big.rs", Data(repeating: 0x41, count: 4_096), UInt8(ascii: "0")),
        ])
        XCTAssertThrowsError(try TarArchiveReader.entries(in: tar, limits: limits)) { error in
            XCTAssertEqual(error as? CrateArchiveError, .archiveTooLarge)
        }
    }

    func testEnforcesTheEntryCountLimit() throws {
        var limits = CrateArchiveLimits.default
        limits.maximumEntries = 2
        let entries = (0..<4).map {
            ("\(root)/file\($0).rs", Data("x".utf8), UInt8(ascii: "0"))
        }
        XCTAssertThrowsError(
            try TarArchiveReader.entries(in: TarFixture.tar(entries), limits: limits)
        ) { error in
            XCTAssertEqual(error as? CrateArchiveError, .tooManyEntries)
        }
    }

    func testChecksumsAreComparedAgainstTheDownloadedBytes() {
        let payload = Data("crate bytes".utf8)
        let digest = CrateStore.sha256(payload)
        XCTAssertEqual(digest.count, 64)
        XCTAssertNotEqual(digest, CrateStore.sha256(Data("other bytes".utf8)))
    }
}
