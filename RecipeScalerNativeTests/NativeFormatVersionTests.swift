import XCTest
import RecipeScalerCore

final class NativeFormatVersionTests: XCTestCase {
    func testNormalizeFromExplicitVersion() {
        XCTAssertEqual(normalizeNativeFormatVersion(version: "1.0", type: nil), .v1_0)
        XCTAssertEqual(normalizeNativeFormatVersion(version: "1.4", type: nil), .v1_4)
    }

    func testNormalizeFromTypeWhenVersionMissing() {
        XCTAssertEqual(normalizeNativeFormatVersion(version: nil, type: "recipes-simple"), .v1_0)
        XCTAssertEqual(normalizeNativeFormatVersion(version: nil, type: "recipes-v1.2"), .v1_2)
        XCTAssertEqual(normalizeNativeFormatVersion(version: nil, type: "recipes-v1.4"), .v1_4)
    }

    func testNormalizeDefaultsToV10() {
        XCTAssertEqual(normalizeNativeFormatVersion(version: nil, type: nil), .v1_0)
        XCTAssertEqual(normalizeNativeFormatVersion(version: "", type: "unknown"), .v1_0)
        XCTAssertEqual(normalizeNativeFormatVersion(version: "9.9", type: nil), .v1_0)
    }

    func testVersionOrdering() {
        XCTAssertTrue(NativeFormatVersion.v1_0 < .v1_4)
        XCTAssertTrue(NativeFormatVersion.v1_4.supportsFolders)
        XCTAssertFalse(NativeFormatVersion.v1_3.supportsFolders)
        XCTAssertTrue(NativeFormatVersion.v1_3.supportsServings)
        XCTAssertTrue(NativeFormatVersion.v1_2.supportsNutrition)
    }

    // MARK: - v1.5 (finding #15)

    func testNormalizeFromV15VersionAndType() {
        XCTAssertEqual(normalizeNativeFormatVersion(version: "1.5", type: nil), .v1_5)
        XCTAssertEqual(normalizeNativeFormatVersion(version: nil, type: "recipes-v1.5"), .v1_5)
    }

    func testV15Properties() {
        XCTAssertEqual(NativeFormatVersion.v1_5.rawValue, "1.5")
        XCTAssertEqual(NativeFormatVersion.v1_5.typeString, "recipes-v1.5")
        XCTAssertTrue(NativeFormatVersion.v1_5.supportsAmountText)
        XCTAssertTrue(NativeFormatVersion.v1_5.supportsFolders)
        XCTAssertTrue(NativeFormatVersion.v1_5.supportsServings)
        XCTAssertTrue(NativeFormatVersion.v1_5.supportsNutrition)
    }

    func testV15Ordering() {
        XCTAssertTrue(NativeFormatVersion.v1_4 < .v1_5)
        XCTAssertFalse(NativeFormatVersion.v1_4.supportsAmountText)
        XCTAssertTrue((NativeFormatVersion.v1_5 < .v1_5) == false)
        // supportsAmountText gates correctly on older versions
        XCTAssertFalse(NativeFormatVersion.v1_3.supportsAmountText)
    }

    func testV15IsCaseIterableLatest() {
        XCTAssertEqual(NativeFormatVersion.allCases.last, .v1_5)
    }
}
