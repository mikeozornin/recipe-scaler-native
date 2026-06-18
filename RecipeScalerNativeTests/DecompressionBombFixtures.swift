import Foundation
import zlib
import ZIPFoundation
@testable import RecipeScalerCore

/// Test helpers for crafting gzip-bomb and zip-bomb fixtures at runtime.
///
/// All fixtures are generated in `setUp` (temporary directory) — no binary assets
/// are committed to the repo. Sizes are intentionally small to keep tests fast
/// (< 100 ms each); real-world limits are exercised through the actual constants
/// in `ThirdPartyImportLimits`.
enum DecompressionBombFixtures {

    // MARK: - Gzip

    /// Build a gzip stream whose decompressed payload is `decompressedSize` bytes of
    /// repeating `0x41` (compresses very well — a real "bomb" reproducer).
    static func makeGzip(decompressedSize: Int, fillByte: UInt8 = 0x41) throws -> Data {
        let raw = Data(repeating: fillByte, count: decompressedSize)
        return try gzipCompress(raw)
    }

    /// Gzip-encode an arbitrary payload. Mirrors the format `Gunzip.decompress`
    /// expects: magic `0x1f 0x8b`, deflate stream, CRC32, ISIZE.
    static func gzipCompress(_ raw: Data) throws -> Data {
        // Use zlib deflate with gzip wrapper (windowBits = 15 + 16).
        var stream = z_stream()
        var status = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            15 + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else {
            throw FixtureError.deflateInitFailed(status)
        }
        defer { deflateEnd(&stream) }

        var output = Data()
        let chunkSize = 65_536
        var inputBytes = [UInt8](raw)
        var inputOffset = 0
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        stream.next_in = inputOffset < inputBytes.count
            ? UnsafeMutablePointer<Bytef>(&inputBytes) + inputOffset
            : nil
        stream.avail_in = UInt32(inputBytes.count)

        repeat {
            stream.next_out = UnsafeMutablePointer<Bytef>(&buffer)
            stream.avail_out = UInt32(chunkSize)
            status = deflate(&stream, Z_FINISH)
            let produced = chunkSize - Int(stream.avail_out)
            if produced > 0 {
                output.append(buffer, count: produced)
            }
            inputOffset = inputBytes.count - Int(stream.avail_in)
        } while status == Z_OK

        guard status == Z_STREAM_END else {
            throw FixtureError.deflateFailed(status)
        }
        _ = inputOffset
        return output
    }

    // MARK: - ZIP

    /// Build a ZIP archive at `url` containing a single entry `name` whose decompressed
    /// payload is `decompressedSize` bytes of repeating `fillByte`. Compression is
    /// deferred to ZIPFoundation, which produces a legitimately small on-disk archive.
    @discardableResult
    static func makeZip(
        at url: URL,
        entryName: String,
        decompressedSize: Int,
        fillByte: UInt8 = 0x41
    ) throws -> URL {
        try? FileManager.default.removeItem(at: url)
        let payload = Data(repeating: fillByte, count: decompressedSize)
        guard let archive = Archive(url: url, accessMode: .create) else {
            throw FixtureError.archiveCreateFailed(url)
        }
        try archive.addEntry(
            with: entryName,
            type: .file,
            uncompressedSize: UInt32(payload.count),
            provider: { position, size in
                payload.subdata(in: Int(position)..<Int(position + size))
            }
        )
        return url
    }

    /// Build a ZIP archive at `url` containing `count` entries of `decompressedSize` bytes
    /// each, named `prefix-<i>.<suffix>`.
    @discardableResult
    static func makeZip(
        at url: URL,
        entryCount: Int,
        entryNamePrefix: String,
        entrySuffix: String,
        decompressedSize: Int,
        fillByte: UInt8 = 0x41
    ) throws -> URL {
        try? FileManager.default.removeItem(at: url)
        let payload = Data(repeating: fillByte, count: decompressedSize)
        guard let archive = Archive(url: url, accessMode: .create) else {
            throw FixtureError.archiveCreateFailed(url)
        }
        for i in 0..<entryCount {
            try archive.addEntry(
                with: "\(entryNamePrefix)-\(i).\(entrySuffix)",
                type: .file,
                uncompressedSize: UInt32(payload.count),
                provider: { position, size in
                    payload.subdata(in: Int(position)..<Int(position + size))
                }
            )
        }
        return url
    }

    enum FixtureError: Error, CustomStringConvertible {
        case deflateInitFailed(Int32)
        case deflateFailed(Int32)
        case archiveCreateFailed(URL)

        var description: String {
            switch self {
            case .deflateInitFailed(let s): return "deflateInit2_ failed: \(s)"
            case .deflateFailed(let s): return "deflate failed: \(s)"
            case .archiveCreateFailed(let u): return "Archive(create) failed: \(u)"
            }
        }
    }

    /// Scratch directory unique per-test (avoid collisions when tests run in parallel).
    static func makeTempURL(prefix: String = "bomb", suffix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let name = "\(prefix)-\(UUID().uuidString).\(suffix)"
        return dir.appendingPathComponent(name)
    }
}
