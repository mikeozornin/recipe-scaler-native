import XCTest
import RecipeScalerCore

/// TP-1: `Gunzip.decompress` byte cap (review #3 — gzip decompression bomb).
///
/// These tests are part of the TDD RED phase: they assert behaviour that the
/// current implementation does NOT provide (the `maxOutputBytes` parameter
/// exists but is ignored). They are expected to FAIL until Phase B lands.
final class GunzipDecompressionTests: XCTestCase {

    // MARK: - TP-1.1 Oversized gzip rejected

    /// A gzip stream that decompresses to 1 MB must be rejected when the caller
    /// passes `maxOutputBytes: 64 KB`.
    func testTP1_1_OversizedGzipRejected() throws {
        let bomb = try DecompressionBombFixtures.makeGzip(decompressedSize: 1_000_000)
        XCTAssertLessThan(bomb.count, 1_000_000, "sanity: gzip should be much smaller")

        XCTAssertThrowsError(
            try Gunzip.decompress(bomb, fileName: "bomb.paprikarecipe", maxOutputBytes: 65_536)
        ) { error in
            guard case .entrySizeLimitExceeded(let fileName) = error as? ThirdPartyImportError else {
                return XCTFail("Expected .entrySizeLimitExceeded, got \(error)")
            }
            XCTAssertEqual(fileName, "bomb.paprikarecipe")
        }
    }

    // MARK: - TP-1.2 Valid gzip under limit passes

    func testTP1_2_ValidGzipUnderLimitPasses() throws {
        let payload = Data(repeating: 0x42, count: 32_000)
        let gz = try DecompressionBombFixtures.gzipCompress(payload)

        let out = try Gunzip.decompress(gz, fileName: "ok.paprikarecipe", maxOutputBytes: 65_536)
        XCTAssertEqual(out.count, 32_000)
        XCTAssertEqual(out.first, 0x42)
    }

    // MARK: - TP-1.3 Backward-compatible default `.max`

    /// Calls without an explicit `maxOutputBytes` keep the legacy behaviour.
    func testTP1_3_DefaultMaxKeepsBackwardCompat() throws {
        let payload = Data(repeating: 0x43, count: 1024)
        let gz = try DecompressionBombFixtures.gzipCompress(payload)

        let out = try Gunzip.decompress(gz, fileName: "legacy.paprikarecipe")
        XCTAssertEqual(out.count, 1024)
    }

    // MARK: - TP-1.4 Bad gzip still throws `.gzipFailed`

    func testTP1_4_BadGzipStillThrows() throws {
        var bad = Data([0x1f, 0x8b])
        bad.append(Data(repeating: 0xFF, count: 64))

        XCTAssertThrowsError(
            try Gunzip.decompress(bad, fileName: "broken.gz", maxOutputBytes: 65_536)
        ) { error in
            guard case .gzipFailed(let fileName) = error as? ThirdPartyImportError else {
                return XCTFail("Expected .gzipFailed, got \(error)")
            }
            XCTAssertEqual(fileName, "broken.gz")
        }
    }

    // MARK: - TP-1.5 Cap aborts inflate early (perf guard)

    /// A real decompression bomb (10 MB decompresses to a few KB) must be rejected
    /// in well under 100 ms — i.e. the loop must abort as soon as it crosses the
    /// 64 KB cap, NOT keep inflating the full stream.
    func testTP1_5_CapAbortsInflateEarly() throws {
        let bomb = try DecompressionBombFixtures.makeGzip(decompressedSize: 10_000_000)
        XCTAssertLessThan(bomb.count, 100_000, "sanity: bomb should be small")

        let start = Date()
        XCTAssertThrowsError(
            try Gunzip.decompress(bomb, fileName: "perf.gz", maxOutputBytes: 65_536)
        ) { error in
            guard case .entrySizeLimitExceeded = error as? ThirdPartyImportError else {
                return XCTFail("Expected .entrySizeLimitExceeded, got \(error)")
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed,
            0.100,
            "Cap should abort inflate in well under 100 ms; took \(elapsed * 1000) ms"
        )
    }

    // MARK: - TP-1.6 Exact boundary: output == max is allowed

    /// When decompressed output exactly equals `maxOutputBytes`, it must succeed —
    /// the cap uses `>`, not `>=`.
    func testTP1_6_ExactBoundaryAllowed() throws {
        let size = 1_000
        let payload = Data(repeating: 0x55, count: size)
        let gz = try DecompressionBombFixtures.gzipCompress(payload)

        let out = try Gunzip.decompress(gz, fileName: "boundary.gz", maxOutputBytes: size)
        XCTAssertEqual(out.count, size)
    }

    // MARK: - TP-1.7 One byte over the cap is rejected

    func testTP1_7_OneByteOverRejected() throws {
        let payload = Data(repeating: 0x55, count: 1_001)
        let gz = try DecompressionBombFixtures.gzipCompress(payload)

        XCTAssertThrowsError(
            try Gunzip.decompress(gz, fileName: "over.gz", maxOutputBytes: 1_000)
        ) { error in
            guard case .entrySizeLimitExceeded = error as? ThirdPartyImportError else {
                return XCTFail("Expected .entrySizeLimitExceeded, got \(error)")
            }
        }
    }
}
