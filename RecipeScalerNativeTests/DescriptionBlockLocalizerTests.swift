import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

/// Tests for `DescriptionBlockLocalizer` — the Native-layer bridge that resolves
/// Core parser's structural metadata signals (`prepTime` / `cookTime` /
/// `durationMinutes` / `difficulty`) into localized `.paragraph` blocks before
/// they reach the Y.Doc writer.
///
/// See review #30: Core parsers must remain i18n-free; localization happens
/// in the Native layer at apply-time.
final class DescriptionBlockLocalizerTests: XCTestCase {

    // MARK: - Pass-through cases

    func testParagraphIsPassedThroughUnchanged() {
        XCTAssertEqual(
            DescriptionBlockLocalizer.localize(.paragraph("notes")),
            .paragraph("notes")
        )
    }

    func testHeadingIsPassedThroughUnchanged() {
        XCTAssertEqual(
            DescriptionBlockLocalizer.localize(.heading(level: 3, "Section")),
            .heading(level: 3, "Section")
        )
    }

    func testOrderedListItemIsPassedThroughUnchanged() {
        XCTAssertEqual(
            DescriptionBlockLocalizer.localize(.orderedListItem("step")),
            .orderedListItem("step")
        )
    }

    // MARK: - difficulty (free-form, pass-through as paragraph)

    func testDifficultyBecomesParagraphVerbatim() {
        XCTAssertEqual(
            DescriptionBlockLocalizer.localize(.difficulty("Easy")),
            .paragraph("Easy")
        )
    }

    func testDifficultyNonASCIIIsPreserved() {
        XCTAssertEqual(
            DescriptionBlockLocalizer.localize(.difficulty("Лёгкий")),
            .paragraph("Лёгкий")
        )
    }

    // MARK: - prepTime / cookTime / durationMinutes (localized labels)

    func testPrepTimeBecomesLocalizedParagraphInEnglish() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.en)

        let result = DescriptionBlockLocalizer.localize(.prepTime("10 min"))
        guard case let .paragraph(text) = result else {
            return XCTFail("Expected .paragraph, got \(result)")
        }
        XCTAssertTrue(text.hasPrefix("Prep:"), "en prefix should be 'Prep:', got: \(text)")
        XCTAssertTrue(text.contains("10 min"), "value must be interpolated, got: \(text)")
    }

    func testPrepTimeBecomesLocalizedParagraphInRussian() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.ru)

        let result = DescriptionBlockLocalizer.localize(.prepTime("10 min"))
        guard case let .paragraph(text) = result else {
            return XCTFail("Expected .paragraph, got \(result)")
        }
        XCTAssertTrue(text.hasPrefix("Подготовка:"), "ru prefix should be 'Подготовка:', got: \(text)")
        XCTAssertTrue(text.contains("10 min"), "value must be interpolated, got: \(text)")
    }

    func testCookTimeBecomesLocalizedParagraphInEnglish() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.en)

        let result = DescriptionBlockLocalizer.localize(.cookTime("20 min"))
        guard case let .paragraph(text) = result else {
            return XCTFail("Expected .paragraph, got \(result)")
        }
        XCTAssertTrue(text.hasPrefix("Cook:"), "en prefix should be 'Cook:', got: \(text)")
        XCTAssertTrue(text.contains("20 min"), "value must be interpolated, got: \(text)")
    }

    func testCookTimeBecomesLocalizedParagraphInRussian() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.ru)

        let result = DescriptionBlockLocalizer.localize(.cookTime("20 min"))
        guard case let .paragraph(text) = result else {
            return XCTFail("Expected .paragraph, got \(result)")
        }
        XCTAssertTrue(text.hasPrefix("Готовка:"), "ru prefix should be 'Готовка:', got: \(text)")
        XCTAssertTrue(text.contains("20 min"), "value must be interpolated, got: \(text)")
    }

    func testDurationMinutesBecomesLocalizedParagraphInEnglish() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.en)

        let result = DescriptionBlockLocalizer.localize(.durationMinutes(30))
        guard case let .paragraph(text) = result else {
            return XCTFail("Expected .paragraph, got \(result)")
        }
        XCTAssertTrue(text.contains("30"), "minutes value must be present, got: \(text)")
        XCTAssertTrue(text.lowercased().contains("min"), "en unit should contain 'min', got: \(text)")
    }

    func testDurationMinutesBecomesLocalizedParagraphInRussian() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.ru)

        let result = DescriptionBlockLocalizer.localize(.durationMinutes(30))
        guard case let .paragraph(text) = result else {
            return XCTFail("Expected .paragraph, got \(result)")
        }
        XCTAssertTrue(text.contains("30"), "minutes value must be present, got: \(text)")
        XCTAssertTrue(text.contains("мин"), "ru unit should contain 'мин', got: \(text)")
    }

    // MARK: - Array form

    func testLocalizeArrayPreservesOrderAndResolvesAllSignals() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.en)

        let input: [DescriptionBlock] = [
            .prepTime("5 min"),
            .cookTime("25 min"),
            .durationMinutes(30),
            .difficulty("Medium"),
            .paragraph("Rest overnight"),
            .orderedListItem("Combine"),
            .heading(level: 3, "Sauce")
        ]

        let result = DescriptionBlockLocalizer.localize(input)
        XCTAssertEqual(result.count, input.count)

        // First four must be paragraphs (resolved), last three pass-through.
        if case .paragraph = result[0] {} else { XCTFail("prepTime should resolve to paragraph") }
        if case .paragraph = result[1] {} else { XCTFail("cookTime should resolve to paragraph") }
        if case .paragraph = result[2] {} else { XCTFail("durationMinutes should resolve to paragraph") }
        XCTAssertEqual(result[3], .paragraph("Medium"))
        XCTAssertEqual(result[4], .paragraph("Rest overnight"))
        XCTAssertEqual(result[5], .orderedListItem("Combine"))
        XCTAssertEqual(result[6], .heading(level: 3, "Sauce"))
    }
}
