//
//  SyncErrorCodeTests.swift
//
//  Spec 031 / MIK-129 — verifies the Socket.IO `sync_error` classification pipeline:
//    1. `SyncErrorCode.from(code:legacyMessage:fallback:)` resolves future dot-key
//       `code` values directly.
//    2. Falls back to legacy English substring matching on `legacyMessage`
//       (preserves behavior with un-migrated servers).
//    3. Returns the explicit `fallback` when neither matches.
//    4. `localizedMessage` never leaks the raw dot-key or English — always
//       resolves through `Bundle.currentLocalizedString`.
//

import XCTest
@testable import RecipeScalerNative

final class SyncErrorCodeTests: XCTestCase {

    // MARK: - Future dot-key path

    func testFrom_resolvesKnownCode_ownership() {
        let code = SyncErrorCode.from(code: "sync.error.ownership", legacyMessage: nil)
        XCTAssertEqual(code, .ownershipFailed)
    }

    func testFrom_resolvesKnownCode_recipeDeleted() {
        let code = SyncErrorCode.from(code: "sync.error.recipe-deleted", legacyMessage: nil)
        XCTAssertEqual(code, .recipeDeleted)
    }

    func testFrom_resolvesKnownCode_emptyUpdate() {
        let code = SyncErrorCode.from(code: "sync.error.empty-update", legacyMessage: nil)
        XCTAssertEqual(code, .emptyUpdate)
    }

    func testFrom_resolvesKnownCode_invalidUpdate() {
        let code = SyncErrorCode.from(code: "sync.error.invalid-update", legacyMessage: nil)
        XCTAssertEqual(code, .invalidUpdate)
    }

    func testFrom_resolvesKnownCode_generic() {
        let code = SyncErrorCode.from(code: "sync.error.generic", legacyMessage: nil)
        XCTAssertEqual(code, .generic)
    }

    func testFrom_codeTakesPrecedenceOverLegacyMessage() {
        // Even if legacyMessage matches a different pattern, the `code` wins.
        let code = SyncErrorCode.from(
            code: "sync.error.recipe-deleted",
            legacyMessage: "Ownership validation failed"
        )
        XCTAssertEqual(code, .recipeDeleted)
    }

    func testFrom_unknownCodeFallsBackToLegacyMessage() {
        // Unknown dot-key in `code` → ignore, try legacy substring.
        let code = SyncErrorCode.from(
            code: "sync.error.future-unknown",
            legacyMessage: "Recipe is deleted"
        )
        XCTAssertEqual(code, .recipeDeleted)
    }

    // MARK: - Legacy English substring path

    func testFrom_legacyMessage_ownership() {
        let code = SyncErrorCode.from(code: nil, legacyMessage: "Ownership validation failed for recipe abc")
        XCTAssertEqual(code, .ownershipFailed)
    }

    func testFrom_legacyMessage_recipeDeleted() {
        let code = SyncErrorCode.from(code: nil, legacyMessage: "Recipe is deleted")
        XCTAssertEqual(code, .recipeDeleted)
    }

    func testFrom_legacyMessage_invalidUpdate() {
        let code = SyncErrorCode.from(code: nil, legacyMessage: "Invalid update payload")
        XCTAssertEqual(code, .invalidUpdate)
    }

    func testFrom_legacyMessage_empty() {
        let code = SyncErrorCode.from(code: nil, legacyMessage: "Empty update body")
        XCTAssertEqual(code, .emptyUpdate)
    }

    // MARK: - Fallbacks

    func testFrom_unknownLegacyMessageReturnsDefaultFallback() {
        let code = SyncErrorCode.from(
            code: nil,
            legacyMessage: "Some future error not yet classified"
        )
        XCTAssertEqual(code, .generic)
    }

    func testFrom_unknownLegacyMessageReturnsExplicitFallback() {
        let code = SyncErrorCode.from(
            code: nil,
            legacyMessage: "weird unclassified thing",
            fallback: .ownershipFailed
        )
        XCTAssertEqual(code, .ownershipFailed)
    }

    func testFrom_nilInputsReturnFallback() {
        XCTAssertEqual(SyncErrorCode.from(code: nil, legacyMessage: nil), .generic)
        XCTAssertEqual(
            SyncErrorCode.from(code: nil, legacyMessage: nil, fallback: .recipeDeleted),
            .recipeDeleted
        )
    }

    func testFrom_emptyCodeFallsBackToLegacyMessage() {
        let code = SyncErrorCode.from(code: "", legacyMessage: "Ownership validation failed")
        XCTAssertEqual(code, .ownershipFailed)
    }

    func testFrom_emptyLegacyMessageFallsBack() {
        let code = SyncErrorCode.from(code: nil, legacyMessage: "")
        XCTAssertEqual(code, .generic)
    }

    // MARK: - CaseIterable / raw values

    func test_allCasesCoverContractCatalog() {
        // The five cases enumerated in specs/031-error-i18n/sync-error-codes.md.
        XCTAssertEqual(
            Set(SyncErrorCode.allCases.map(\.rawValue)),
            [
                "sync.error.ownership",
                "sync.error.recipe-deleted",
                "sync.error.empty-update",
                "sync.error.invalid-update",
                "sync.error.generic",
            ]
        )
    }

    // MARK: - Localization

    func test_localizedMessage_neverLeaksRawDotKey() {
        // For every case, the localized message must differ from the rawValue —
        // i.e. the bundle must have a real translation, not return the key as-is.
        for code in SyncErrorCode.allCases {
            let message = code.localizedMessage
            XCTAssertNotEqual(
                message,
                code.rawValue,
                "localizedMessage for \(code.rawValue) leaked the dot-key (missing translation?)"
            )
        }
    }

    func test_localizedMessage_neverLeaksLegacyEnglish() {
        // The legacy English strings must never appear in any localizedMessage.
        let englishLeakSubstrings = [
            "Ownership validation failed",
            "Recipe is deleted",
            "Invalid update",
            "Empty",
            "Unknown sync error"
        ]
        for code in SyncErrorCode.allCases {
            let message = code.localizedMessage
            for leak in englishLeakSubstrings {
                XCTAssertFalse(
                    message.contains(leak),
                    "localizedMessage for \(code.rawValue) leaked English substring: \(leak)"
                )
            }
        }
    }

    func test_localizedMessage_genericKeyIsLocalized() {
        // Specifically: the .generic case used to fall through to `return message`
        // and leak raw English. Verify it is now localized.
        let message = SyncErrorCode.generic.localizedMessage
        XCTAssertNotEqual(message, "Unknown sync error")
        XCTAssertFalse(message.isEmpty)
    }
}
