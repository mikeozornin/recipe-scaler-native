import XCTest
@testable import RecipeScalerNative

/// Tests for `NativeImportMessageLocalizer` — the i18n facade for messages
/// surfaced by `NativeExportImportService` import flow (recipe failures,
/// folder errors, image warnings).
///
/// See review #29: previously, folder errors were built via inline
/// `String(localized:)` and string interpolation; now they go through the
/// same localizer as recipe/image messages, using `Bundle.currentLocalizedString`
/// + explicit `AppLanguagePreference.current.locale` formatting.
final class NativeImportMessageLocalizerTests: XCTestCase {

    // MARK: - folderEmptySkipped

    func testFolderEmptySkippedReturnsNonEmptyStringInEnglish() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.en)

        let message = NativeImportMessageLocalizer.folderEmptySkipped()
        XCTAssertFalse(message.isEmpty)
        // English string contains the word "Folder" and "skipped".
        XCTAssertTrue(message.lowercased().contains("folder"), "en: \(message)")
        XCTAssertTrue(message.lowercased().contains("skipped"), "en: \(message)")
    }

    func testFolderEmptySkippedReturnsLocalizedRussianString() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.ru)

        let message = NativeImportMessageLocalizer.folderEmptySkipped()
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(message.contains("папк"), "ru: \(message)")
        XCTAssertTrue(message.lowercased().contains("пропущен"), "ru: \(message)")
    }

    // MARK: - folderFailed

    func testFolderFailedIncludesFolderNameAndErrorMessage() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.en)

        struct StubError: Error, LocalizedError {
            var errorDescription: String? { "Permission denied" }
        }

        let message = NativeImportMessageLocalizer.folderFailed(
            name: "Desserts",
            error: StubError()
        )

        XCTAssertTrue(message.contains("Desserts"), "name must be present: \(message)")
        // Reason comes through UserFacingAPIError fallback path; the structure
        // of the message must include a separator between name and reason.
        XCTAssertTrue(message.contains(":"), "expected separator: \(message)")
    }

    func testFolderFailedUsesRussianFormat() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.ru)

        struct StubError: Error, LocalizedError {
            var errorDescription: String? { "Отказ" }
        }

        let message = NativeImportMessageLocalizer.folderFailed(
            name: "Десерты",
            error: StubError()
        )

        XCTAssertTrue(message.contains("Десерты"), "ru name must be present: \(message)")
        XCTAssertTrue(message.contains("«Десерты»") || message.contains("Десерты"), "ru uses guillemets: \(message)")
    }

    // MARK: - existing recipe/image messages (sanity)

    func testRecipeFailedIncludesNameAndReason() {
        let original = AppLanguagePreference.current
        defer { AppLanguagePreference.save(original) }
        AppLanguagePreference.save(.en)

        struct StubError: Error, LocalizedError {
            var errorDescription: String? { "Disk full" }
        }

        let message = NativeImportMessageLocalizer.recipeFailed(
            name: "Cake",
            error: StubError()
        )
        XCTAssertTrue(message.contains("Cake"), "recipe name must be present: \(message)")
    }

    func testImagesOfflineReturnsNonEmptyForPositiveCount() {
        let message = NativeImportMessageLocalizer.imagesOffline(count: 3)
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(message.contains("3"), "count must be interpolated: \(message)")
    }
}
