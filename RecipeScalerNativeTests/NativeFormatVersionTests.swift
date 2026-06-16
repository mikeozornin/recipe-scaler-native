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
}
