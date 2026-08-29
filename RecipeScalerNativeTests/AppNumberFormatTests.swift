import XCTest
@testable import RecipeScalerNative

final class AppNumberFormatTests: XCTestCase {
    private let ru = Locale(identifier: "ru_RU")
    private let en = Locale(identifier: "en_US")

    func testRuLocaleUsesComma() {
        XCTAssertEqual(AppNumberFormat.string(9.2, maximumFractionDigits: 1, locale: ru), "9,2")
        XCTAssertEqual(AppNumberFormat.string(1.25, maximumFractionDigits: 2, locale: ru), "1,25")
        XCTAssertEqual(AppNumberFormat.string(9.2, maximumFractionDigits: 1, locale: en), "9.2")
    }

    func testIntegralValueHasNoFractionPart() {
        XCTAssertEqual(AppNumberFormat.string(700, maximumFractionDigits: 2, locale: ru), "700")
        XCTAssertEqual(AppNumberFormat.string(2.0, maximumFractionDigits: 1, locale: en), "2")
    }

    func testTrailingZerosAreTrimmed() {
        XCTAssertEqual(AppNumberFormat.string(1.50, maximumFractionDigits: 2, locale: ru), "1,5")
        XCTAssertEqual(AppNumberFormat.string(0.10, maximumFractionDigits: 2, locale: en), "0.1")
    }

    func testNonFiniteReturnsEmpty() {
        XCTAssertEqual(AppNumberFormat.string(Double.nan, maximumFractionDigits: 2, locale: ru), "")
        XCTAssertEqual(AppNumberFormat.string(.infinity, maximumFractionDigits: 2, locale: ru), "")
        XCTAssertEqual(AppNumberFormat.string(-.infinity, maximumFractionDigits: 2, locale: ru), "")
    }

    func testNoGroupingSeparatorForLargeNumbers() {
        XCTAssertEqual(AppNumberFormat.string(12345.5, maximumFractionDigits: 1, locale: ru), "12345,5")
        XCTAssertEqual(AppNumberFormat.string(12345.5, maximumFractionDigits: 1, locale: en), "12345.5")
    }

    func testMinimumFractionDigitsPinsFractionLength() {
        XCTAssertEqual(
            AppNumberFormat.string(1.5, minimumFractionDigits: 1, maximumFractionDigits: 2, locale: ru),
            "1,5"
        )
    }

    func testParseAcceptsBothSeparatorsInAnyLocale() {
        XCTAssertEqual(AppNumberFormat.parse("9,2", locale: ru), 9.2)
        XCTAssertEqual(AppNumberFormat.parse("9.2", locale: ru), 9.2)
        XCTAssertEqual(AppNumberFormat.parse("9,2", locale: en), 9.2)
        XCTAssertEqual(AppNumberFormat.parse("9.2", locale: en), 9.2)
    }

    func testParseRoundTripWithFormattedRuOutput() {
        let formatted = AppNumberFormat.string(1.25, maximumFractionDigits: 2, locale: ru)
        XCTAssertEqual(formatted, "1,25")
        XCTAssertEqual(AppNumberFormat.parse(formatted, locale: ru), 1.25)
    }

    func testParseNormalizesSpaces() {
        XCTAssertEqual(AppNumberFormat.parse(" 1 234,5 ", locale: ru), 1234.5)
        XCTAssertEqual(AppNumberFormat.parse("\u{00A0}12,5", locale: ru), 12.5)
    }

    func testParseMixedSeparatorsUsesLastAsDecimal() {
        XCTAssertEqual(AppNumberFormat.parse("1.234,5", locale: ru), 1234.5)
        XCTAssertEqual(AppNumberFormat.parse("1,234.5", locale: en), 1234.5)
    }

    func testParseInvalidReturnsNil() {
        XCTAssertNil(AppNumberFormat.parse("", locale: ru))
        XCTAssertNil(AppNumberFormat.parse("   ", locale: ru))
        XCTAssertNil(AppNumberFormat.parse("abc", locale: ru))
    }

    func testCurrentFollowsAppLanguagePreference() {
        let preference = AppLanguagePreference.current
        XCTAssertEqual(AppNumberFormat.current.identifier, preference.locale.identifier)
    }
}
