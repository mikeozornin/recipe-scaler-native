//
//  RecipeAccentColorTests.swift
//  RecipeScalerNativeTests
//

import XCTest
@testable import RecipeScalerNative

final class RecipeAccentColorTests: XCTestCase {

    // MARK: - normalizedStored

    func testEmptyFallsBackToDefault() {
        XCTAssertEqual(
            RecipeAccentColor.normalizedStored(""),
            "oklch(0.65 0.25 270)"
        )
    }

    func testWhitespaceOnlyFallsBackToDefault() {
        XCTAssertEqual(
            RecipeAccentColor.normalizedStored("   \n\t "),
            "oklch(0.65 0.25 270)"
        )
    }

    func testUppercaseHexIsIdempotent() {
        XCTAssertEqual(RecipeAccentColor.normalizedStored("#FF00AA"), "#FF00AA")
    }

    func testLowercaseHexIsUppercased() {
        XCTAssertEqual(RecipeAccentColor.normalizedStored("#ff00aa"), "#FF00AA")
    }

    func testShortHexIsUppercased() {
        XCTAssertEqual(RecipeAccentColor.normalizedStored("#abc"), "#ABC")
    }

    func testLeadingTrailingWhitespaceIsTrimmed() {
        XCTAssertEqual(RecipeAccentColor.normalizedStored("  #ff00aa  "), "#FF00AA")
    }

    func testOklchIsReturnedAsIs() {
        let oklch = "oklch(0.65 0.25 270)"
        XCTAssertEqual(RecipeAccentColor.normalizedStored(oklch), oklch)
    }

    /// Regression for review finding #60: the old `DocumentManager.normalizeColor`
    /// parsed its guard as `(hasPrefix("#") && count == 7) || count == 4` and
    /// uppercased any 4-char string regardless of the `#` prefix.
    func testFourCharNonHexStringIsNotUppercased() {
        XCTAssertEqual(RecipeAccentColor.normalizedStored("abcd"), "abcd")
    }

    /// Regression for review finding #60: 7-char non-`#` strings must NOT be
    /// uppercased either (the old guard would only uppercase 4-char inputs).
    func testSevenCharNonHexStringIsNotUppercased() {
        XCTAssertEqual(RecipeAccentColor.normalizedStored("abcdefg"), "abcdefg")
    }
}
