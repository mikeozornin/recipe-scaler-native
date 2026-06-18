import XCTest
import RecipeScalerCore

/// TP-5: `maxImageBytes` consistency across modules (review #63).
///
/// Three places define the "25 MB" image cap with divergent numeric values:
/// - `ThirdPartyImportLimits.maxImageBytes = 25 * 1024 * 1024`  (26 214 400)
/// - `RecipeScalerCore.ImportPhotoValidator.maxImageBytes = 25_000_000`
/// - `RecipeScalerNative.ImportPhotoValidator.maxImageBytes = 25_000_000`
///
/// After Phase D all three must reference the same underlying constant.
final class ImportLimitsConsistencyTests: XCTestCase {

    /// TP-5.2: numeric value must be the decimal MB 25 000 000 (matches web
    /// `MAX_IMPORT_IMAGE_SIZE_BYTES`).
    func testTP5_2_CoreLimitIsDecimal25MB() {
        XCTAssertEqual(ThirdPartyImportLimits.maxImageBytes, 25_000_000)
    }

    /// TP-5.1 (Core side): Core `ImportPhotoValidator.maxImageBytes` must equal
    /// `ThirdPartyImportLimits.maxImageBytes`.
    func testTP5_1_CoreValidatorSharesCoreConstant() {
        XCTAssertEqual(
            RecipeScalerCore.ImportPhotoValidator.maxImageBytes,
            ThirdPartyImportLimits.maxImageBytes,
            "Core ImportPhotoValidator must reference ThirdPartyImportLimits.maxImageBytes"
        )
    }

    /// New limits introduced for decompression-bomb protection (review #3).
    func testDecompressionLimitsArePositiveAndOrdered() {
        XCTAssertGreaterThan(ThirdPartyImportLimits.maxDecompressedEntryBytes, 0)
        XCTAssertGreaterThan(ThirdPartyImportLimits.maxDecompressedArchiveBytes, 0)
        XCTAssertGreaterThan(ThirdPartyImportLimits.maxGzipJSONBytes, 0)
        XCTAssertGreaterThan(ThirdPartyImportLimits.maxRecipeJSONBytes, 0)

        // Sanity ordering: per-entry < aggregate; gzip/json pre-flight < per-entry.
        XCTAssertLessThanOrEqual(
            ThirdPartyImportLimits.maxGzipJSONBytes,
            ThirdPartyImportLimits.maxDecompressedEntryBytes
        )
        XCTAssertLessThanOrEqual(
            ThirdPartyImportLimits.maxRecipeJSONBytes,
            ThirdPartyImportLimits.maxDecompressedEntryBytes
        )
        XCTAssertLessThan(
            ThirdPartyImportLimits.maxDecompressedEntryBytes,
            ThirdPartyImportLimits.maxDecompressedArchiveBytes
        )
    }
}
