import XCTest
import ZIPFoundation
import RecipeScalerCore

/// TP-2: `ThirdPartyFormatDetector` ZIP guards (review #3 — zip decompression bomb).
///
/// TDD RED phase — these tests are expected to FAIL until Phase B implements the
/// per-entry pre-flight, streaming running total and aggregate byte cap inside
/// `yieldZipEntries`.
final class ThirdPartyFormatDetectorZipBombTests: XCTestCase {

    // MARK: - TP-2.1 Pre-flight catches oversized entry

    /// A ZIP with a single entry whose `uncompressedSize` exceeds `maxEntryBytes`
    /// must be rejected pre-flight, WITHOUT calling `archive.extract`.
    func testTP2_1_PreFlightCatchesOversizedEntry() async throws {
        let url = try DecompressionBombFixtures.makeTempURL(prefix: "tp21", suffix: "paprikarecipes")
        try DecompressionBombFixtures.makeZip(
            at: url,
            entryName: "huge.paprikarecipe",
            decompressedSize: 1_000_000
        )

        let stream = ThirdPartyFormatDetector.enumerateRecipeEntriesStream(
            url: url,
            format: .paprikaArchive,
            maxEntryBytes: 65_536,
            maxArchiveBytes: .max
        )

        do {
            for try await _ in stream { /* no-op */ }
            XCTFail("Expected .entrySizeLimitExceeded, but stream finished cleanly")
        } catch let error as ThirdPartyImportError {
            switch error {
            case .entrySizeLimitExceeded(let fileName):
                XCTAssertEqual(fileName, "huge.paprikarecipe")
            default:
                XCTFail("Expected .entrySizeLimitExceeded, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - TP-2.2 Aggregate cap triggers mid-archive

    /// 20 entries × 100 KB = 2 MB aggregate; cap at 256 KB → must abort before
    /// consuming all entries.
    func testTP2_2_AggregateCapTriggersMidArchive() async throws {
        let url = try DecompressionBombFixtures.makeTempURL(prefix: "tp22", suffix: "zip")
        try DecompressionBombFixtures.makeZip(
            at: url,
            entryCount: 20,
            entryNamePrefix: "r",
            entrySuffix: "crumb",
            decompressedSize: 100_000
        )

        let stream = ThirdPartyFormatDetector.enumerateRecipeEntriesStream(
            url: url,
            format: .croutonArchive,
            maxEntryBytes: .max,
            maxArchiveBytes: 256_000
        )

        do {
            var seen = 0
            for try await _ in stream { seen += 1 }
            XCTFail("Expected .archiveSizeLimitExceeded, got \(seen) entries cleanly")
        } catch let error as ThirdPartyImportError {
            guard case .archiveSizeLimitExceeded = error else {
                return XCTFail("Expected .archiveSizeLimitExceeded, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - TP-2.4 Single-file path not affected by archive guards

    /// `.paprikaSingle` (one gzip file, no ZIP) must NOT be touched by the archive
    /// byte caps — it yields exactly one entry and the gzip cap (TP-1) governs the
    /// per-entry limit.
    func testTP2_4_SingleFilePathIgnoresArchiveGuards() async throws {
        let payload = Data(repeating: 0x44, count: 1_024)
        let gz = try DecompressionBombFixtures.gzipCompress(payload)
        let url = try DecompressionBombFixtures.makeTempURL(prefix: "tp24", suffix: "paprikarecipe")
        try gz.write(to: url)

        let stream = ThirdPartyFormatDetector.enumerateRecipeEntriesStream(
            url: url,
            format: .paprikaSingle,
            // Aggressive caps that would reject anything if applied to single-file.
            maxEntryBytes: 16,
            maxArchiveBytes: 16
        )

        var seen = 0
        for try await entry in stream {
            seen += 1
            XCTAssertEqual(entry.fileName, url.lastPathComponent)
        }
        XCTAssertEqual(seen, 1)
    }

    // MARK: - TP-2.5 Existing happy path still works

    /// Backward compat: with default `.max` caps, a small valid archive yields all
    /// entries without rejection.
    func testTP2_5_DefaultsKeepHappyPathWorking() async throws {
        let url = try DecompressionBombFixtures.makeTempURL(prefix: "tp25", suffix: "zip")
        try DecompressionBombFixtures.makeZip(
            at: url,
            entryCount: 3,
            entryNamePrefix: "r",
            entrySuffix: "crumb",
            decompressedSize: 1_024
        )

        let entries = try await ThirdPartyFormatDetector.enumerateRecipeEntries(
            url: url,
            format: .croutonArchive
        )
        XCTAssertEqual(entries.count, 3)
    }

    // MARK: - TP-2.6 Aggregate streaming guard catches mid-archive overflow

    /// 5 entries × 80 KB. The pre-flight aggregate check uses CD's declared size
    /// and is expected to be accurate here (no spoofing), so this exercises the
    /// real production aggregate path: the running total in the chunk callback
    /// exceeds `maxArchiveBytes` exactly when expected.
    ///
    /// Distinguishes from TP-2.2: archive aggregate is small enough that the
    /// pre-flight happens to PASS for the first ~3 entries and only the
    /// streaming-level check fires later — proving the streaming running total
    /// is wired into the chunk callback (not just the pre-flight).
    func testTP2_6_AggregateStreamingFiresDuringExtraction() async throws {
        let url = try DecompressionBombFixtures.makeTempURL(prefix: "tp26", suffix: "zip")
        // 5 × 80_000 = 400_000 total. Cap at 200_000 → entries 1+2 fit (160_000),
        // entry 3's first chunk pushes over 200_000 → streaming catches.
        try DecompressionBombFixtures.makeZip(
            at: url,
            entryCount: 5,
            entryNamePrefix: "r",
            entrySuffix: "crumb",
            decompressedSize: 80_000
        )

        let stream = ThirdPartyFormatDetector.enumerateRecipeEntriesStream(
            url: url,
            format: .croutonArchive,
            maxEntryBytes: .max,
            maxArchiveBytes: 200_000
        )

        var seen = 0
        do {
            for try await _ in stream { seen += 1 }
            XCTFail("Expected .archiveSizeLimitExceeded; got \(seen) entries cleanly")
        } catch let error as ThirdPartyImportError {
            guard case .archiveSizeLimitExceeded = error else {
                return XCTFail("Expected .archiveSizeLimitExceeded, got \(error)")
            }
            // We must have consumed at least 2 entries before the cap fired.
            XCTAssertGreaterThanOrEqual(seen, 2, "Cap should fire only after the running total exceeds")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - TP-2.7 Zero-byte entry does not crash

    /// An entry whose declared `uncompressedSize == 0` is unusual but not
    /// necessarily malicious. The detector should treat it as `corruptEntry`
    /// (existing `guard !data.isEmpty` semantics), not crash.
    func testTP2_7_ZeroByteEntryDoesNotCrash() async throws {
        let url = try DecompressionBombFixtures.makeTempURL(prefix: "tp27", suffix: "zip")
        try? FileManager.default.removeItem(at: url)
        guard let archive = Archive(url: url, accessMode: .create) else {
            throw NSError(domain: "ThirdPartyFormatDetectorZipBombTests", code: 1)
        }
        let emptyProvider: ZIPFoundation.Provider = { _, _ in Data() }
        try archive.addEntry(
            with: "empty.crumb",
            type: .file,
            uncompressedSize: Int64(0),
            provider: emptyProvider
        )

        let stream = ThirdPartyFormatDetector.enumerateRecipeEntriesStream(
            url: url,
            format: .croutonArchive,
            maxEntryBytes: 1_000,
            maxArchiveBytes: 1_000
        )

        do {
            for try await _ in stream { }
            XCTFail("Expected corruptEntry / emptyArchive; got clean stream")
        } catch let error as ThirdPartyImportError {
            switch error {
            case .corruptEntry, .emptyArchive:
                break
            default:
                XCTFail("Expected corruptEntry / emptyArchive, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
