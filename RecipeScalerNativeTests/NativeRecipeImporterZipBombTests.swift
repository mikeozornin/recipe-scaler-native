import XCTest
import ZIPFoundation
import RecipeScalerCore

/// TP-3: `NativeRecipeImporter.parseZip` guards (review #3 — native export ZIP bomb).
///
/// TDD RED phase — these tests are expected to FAIL until Phase B implements the
/// triple-guard (pre-flight + streaming + aggregate) inside `parseZip`.
final class NativeRecipeImporterZipBombTests: XCTestCase {

    private func makeValidRecipesJson(count: Int = 1) -> Data {
        let recipes = (0..<count).map { idx -> [String: Any] in
            [
                "id": "r\(idx)",
                "name": "Recipe \(idx)",
                "ingredients": [["name": "flour"]]
            ]
        }
        let payload: [String: Any] = [
            "metadata": [
                "version": "1.3",
                "exportDate": "2026-06-18T12:00:00Z",
                "type": "recipes-v1.3",
                "count": count
            ],
            "recipes": recipes
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - TP-3.1 Oversized recipes.json rejected

    /// A ZIP whose `recipes.json` entry decompresses to > `maxRecipeJSONBytes`
    /// (16 MB) must be rejected. The current production limit is enforced
    /// through the per-entry cap passed to `extractEntryBounded`.
    ///
    /// We craft a > 16 MB JSON manifest (mostly whitespace padding inside a
    /// string field — keeps the test memory footprint manageable while
    /// exceeding the pre-flight cap).
    func testTP3_1_OversizedRecipesJsonRejected() throws {
        let url = try DecompressionBombFixtures.makeTempURL(prefix: "tp31", suffix: "zip")
        try? FileManager.default.removeItem(at: url)

        // 17 MB of pad — exceeds maxRecipeJSONBytes (16 MB).
        let paddingName = String(repeating: "x", count: 17_000_000)
        let payload: [String: Any] = [
            "metadata": ["version": "1.3", "exportDate": "2026-06-18T12:00:00Z", "type": "recipes-v1.3"],
            "recipes": [["id": "r1", "name": paddingName, "ingredients": [["name": "flour"]]]]
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertGreaterThan(json.count, ThirdPartyImportLimits.maxRecipeJSONBytes)

        guard let archive = Archive(url: url, accessMode: .create) else {
            throw NSError(domain: "NativeRecipeImporterZipBombTests", code: 1)
        }
        try archive.addEntry(
            with: "recipes.json",
            type: .file,
            uncompressedSize: UInt32(json.count),
            provider: { position, size in
                json.subdata(in: Int(position)..<Int(position + size))
            }
        )

        XCTAssertThrowsError(try NativeRecipeImporter.parse(url: url)) { error in
            switch error as? NativeImportError {
            case .entrySizeLimitExceeded, .jsonSizeLimitExceeded, .archiveSizeLimitExceeded:
                break
            default:
                XCTFail("Expected size-limit error, got \(error)")
            }
        }
    }

    // MARK: - TP-3.2 Oversized image entry rejected

    /// A ZIP with an `images/<id>/full.webp` entry > 25 MB must be rejected by
    /// the per-image cap (`ThirdPartyImportLimits.maxImageBytes`).
    func testTP3_2_OversizedImageRejected() throws {
        let url = try DecompressionBombFixtures.makeTempURL(prefix: "tp32", suffix: "zip")
        try? FileManager.default.removeItem(at: url)

        let recipesJson = makeValidRecipesJson(count: 1)
        let bigImage = Data(repeating: 0xAA, count: 26_000_000)

        guard let archive = Archive(url: url, accessMode: .create) else {
            throw NSError(domain: "NativeRecipeImporterZipBombTests", code: 1)
        }
        try archive.addEntry(
            with: "recipes.json",
            type: .file,
            uncompressedSize: UInt32(recipesJson.count),
            provider: { position, size in
                recipesJson.subdata(in: Int(position)..<Int(position + size))
            }
        )
        try archive.addEntry(
            with: "images/r1/full.webp",
            type: .file,
            uncompressedSize: UInt32(bigImage.count),
            provider: { position, size in
                bigImage.subdata(in: Int(position)..<Int(position + size))
            }
        )

        XCTAssertThrowsError(try NativeRecipeImporter.parse(url: url)) { error in
            switch error as? NativeImportError {
            case .entrySizeLimitExceeded, .archiveSizeLimitExceeded:
                break
            default:
                XCTFail("Expected size-limit error, got \(error)")
            }
        }
    }

    // MARK: - TP-3.4 Valid small export still parses

    /// Backward compat: a small valid ZIP (recipes.json + one small image) must
    /// still parse successfully.
    func testTP3_4_ValidSmallExportParses() throws {
        let url = try DecompressionBombFixtures.makeTempURL(prefix: "tp34", suffix: "zip")
        try? FileManager.default.removeItem(at: url)

        let recipesJson = makeValidRecipesJson(count: 1)
        let tinyImage = Data(repeating: 0xBB, count: 1_024)

        guard let archive = Archive(url: url, accessMode: .create) else {
            throw NSError(domain: "NativeRecipeImporterZipBombTests", code: 1)
        }
        try archive.addEntry(
            with: "recipes.json",
            type: .file,
            uncompressedSize: UInt32(recipesJson.count),
            provider: { position, size in
                recipesJson.subdata(in: Int(position)..<Int(position + size))
            }
        )
        try archive.addEntry(
            with: "images/r1/full.webp",
            type: .file,
            uncompressedSize: UInt32(tinyImage.count),
            provider: { position, size in
                tinyImage.subdata(in: Int(position)..<Int(position + size))
            }
        )

        let parsed = try NativeRecipeImporter.parse(url: url)
        XCTAssertEqual(parsed.recipes.count, 1)
        XCTAssertEqual(parsed.imageEntries.count, 1)
        XCTAssertEqual(parsed.imageEntries.first?.data.count, 1_024)
    }
}
