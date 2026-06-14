//
//  PluralizationTests.swift
//  RecipeScalerNativeTests
//

import XCTest
@testable import RecipeScalerCore

final class PluralizationTests: XCTestCase {

    // MARK: - Category rules

    func testRussianPluralCategories() {
        let locale = Locale(identifier: "ru")
        let expectations: [(Int, PluralCategory)] = [
            (0, .many),
            (1, .one),
            (2, .few),
            (3, .few),
            (4, .few),
            (5, .many),
            (10, .many),
            (11, .many),
            (12, .many),
            (14, .many),
            (15, .many),
            (20, .many),
            (21, .one),
            (22, .few),
            (24, .few),
            (25, .many),
            (30, .many),
            (100, .many),
            (101, .one),
            (102, .few),
            (105, .many),
            (111, .many),
            (121, .one)
        ]
        for (count, expected) in expectations {
            XCTAssertEqual(
                locale.pluralCategory(for: count),
                expected,
                "Russian plural category mismatch for \(count)"
            )
        }
    }

    func testEnglishPluralCategories() {
        let locale = Locale(identifier: "en")
        XCTAssertEqual(locale.pluralCategory(for: 0), .other)
        XCTAssertEqual(locale.pluralCategory(for: 1), .one)
        XCTAssertEqual(locale.pluralCategory(for: 2), .other)
        XCTAssertEqual(locale.pluralCategory(for: 21), .other)
    }

    // MARK: - String formatting

    func testPluralizedStringUsesCorrectForm() {
        let locale = Locale(identifier: "ru")
        let resolver: (String, String?) -> String = { key, _ in
            switch key {
            case "test.item.one": return "%d товар"
            case "test.item.few": return "%d товара"
            case "test.item.many": return "%d товаров"
            default: return key
            }
        }

        XCTAssertEqual(
            Bundle.pluralizedString(key: "test.item", count: 1, locale: locale, localizedString: resolver),
            "1 товар"
        )
        XCTAssertEqual(
            Bundle.pluralizedString(key: "test.item", count: 3, locale: locale, localizedString: resolver),
            "3 товара"
        )
        XCTAssertEqual(
            Bundle.pluralizedString(key: "test.item", count: 11, locale: locale, localizedString: resolver),
            "11 товаров"
        )
        XCTAssertEqual(
            Bundle.pluralizedString(key: "test.item", count: 21, locale: locale, localizedString: resolver),
            "21 товар"
        )
    }

    func testPluralizedStringFallbackToOther() {
        let locale = Locale(identifier: "ru")
        let resolver: (String, String?) -> String = { key, _ in
            switch key {
            case "test.item.other": return "%d things"
            default: return key
            }
        }

        XCTAssertEqual(
            Bundle.pluralizedString(key: "test.item", count: 1, locale: locale, localizedString: resolver),
            "1 things"
        )
    }

    func testPluralizedStringFallbackToBaseKey() {
        let locale = Locale(identifier: "ru")
        let resolver: (String, String?) -> String = { key, _ in
            if key == "test.item" { return "%d fallback" }
            return key
        }

        XCTAssertEqual(
            Bundle.pluralizedString(key: "test.item", count: 5, locale: locale, localizedString: resolver),
            "5 fallback"
        )
    }

    // MARK: - Import error localizer

    func testImportTooManyPhotosUsesConfiguredLimitNotSelectionCount() {
        let error = ImportPhotoValidator.ValidationError.tooMany(count: 10)
        let message = ImportErrorLocalizer.localize(error, bundle: .main)

        XCTAssertTrue(
            message.contains("\(ImportPhotoValidator.maxImages)"),
            "Expected limit \(ImportPhotoValidator.maxImages) in message, got: \(message)"
        )
        XCTAssertFalse(
            message.contains("10"),
            "Should not echo selection count 10, got: \(message)"
        )
    }

    func testImportKeyTooManyPhotosUsesConfiguredLimit() {
        let message = ImportErrorLocalizer.localize(
            NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "import.error-too-many-photos"]),
            bundle: .main
        )

        XCTAssertTrue(message.contains("\(ImportPhotoValidator.maxImages)"), message)
        XCTAssertNotEqual(message, "import.error-too-many-photos")
    }

    func testImportServerMessageTooManyRecipesUsesParsedLimit() {
        let message = ImportErrorLocalizer.localize(
            NSError(
                domain: "test",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "You can import up to 25 recipes at a time."]
            ),
            bundle: .main
        )

        XCTAssertTrue(message.contains("25"), message)
        // English plural and server phrase can match verbatim; Russian/localized runs differ.
        if Locale.current.language.languageCode?.identifier == "ru" {
            XCTAssertNotEqual(message, "You can import up to 25 recipes at a time.")
        }
    }

    func testImportTooManyPhotosUsesSharedStringsInCoreBundle() throws {
        let bundle = Bundle(for: APIClient.self)
        let hasPluralKey = bundle.localizedString(
            forKey: "import.error-too-many-photos.many",
            value: nil,
            table: "Shared"
        ) != "import.error-too-many-photos.many"
        XCTAssertTrue(
            hasPluralKey,
            "RecipeScalerCore test bundle should include Shared.xcstrings plural keys"
        )

        let error = ImportPhotoValidator.ValidationError.tooMany(count: 10)
        let message = ImportErrorLocalizer.localize(error, bundle: bundle)
        if hasPluralKey {
            XCTAssertTrue(message.contains("\(ImportPhotoValidator.maxImages)"), message)
        }
    }
}
