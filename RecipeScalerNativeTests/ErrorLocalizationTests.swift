//
//  ErrorLocalizationTests.swift
//
//  Spec 031 — verifies the error-localization pipeline:
//    1. `DotKeyLocalizer.looksLikeDotKey` correctly classifies messages.
//    2. `DotKeyLocalizer.localize` resolves dot-keys via the runtime bundle,
//       and falls back to a generic key for legacy English strings.
//    3. `APIError.userFacingMessage()` resolves all cases without leaking
//       raw status codes or server-supplied English.
//    4. `UserFacingAPIError.message(for:)` returns "" for CancellationError
//       (callers rely on this to skip UI).
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

final class ErrorLocalizationTests: XCTestCase {

    // MARK: - DotKeyLocalizer

    func testDotKeyDetection_acceptsValidKeys() {
        XCTAssertTrue(DotKeyLocalizer.looksLikeDotKey("assistant.threads.create.failed"))
        XCTAssertTrue(DotKeyLocalizer.looksLikeDotKey("account.profile.load-failed"))
        XCTAssertTrue(DotKeyLocalizer.looksLikeDotKey("a.b"))
        XCTAssertTrue(DotKeyLocalizer.looksLikeDotKey("auth.login.failed"))
    }

    func testDotKeyDetection_rejectsInvalidKeys() {
        XCTAssertFalse(DotKeyLocalizer.looksLikeDotKey("Profile load failed"))
        XCTAssertFalse(DotKeyLocalizer.looksLikeDotKey("assistant error"))
        XCTAssertFalse(DotKeyLocalizer.looksLikeDotKey("Failed: 42"))
        XCTAssertFalse(DotKeyLocalizer.looksLikeDotKey("auth"))             // single segment
        XCTAssertFalse(DotKeyLocalizer.looksLikeDotKey("AUTH.login.failed")) // uppercase rejected
        XCTAssertFalse(DotKeyLocalizer.looksLikeDotKey("auth.Login.failed")) // uppercase segment rejected
        XCTAssertFalse(DotKeyLocalizer.looksLikeDotKey(""))
    }

    func testDotKeyLocalizer_resolvesKnownKey() {
        // Dot-key path: resolved via the runtime bundle. If the key is present,
        // we get back a translated user-facing string different from the key itself.
        let resolved = DotKeyLocalizer.localize(
            message: "api.error.server-generic",
            fallbackKey: "api.error.server-generic"
        )
        XCTAssertNotEqual(resolved, "api.error.server-generic",
                          "Dot-key should be resolved through the bundle, not returned as-is")
    }

    func testDotKeyLocalizer_fallsBackForLegacyEnglish() {
        // Legacy English string — should hit the fallback key, never the raw message.
        let resolved = DotKeyLocalizer.localize(
            message: "Something went wrong on the server",
            fallbackKey: "api.error.server-generic"
        )
        XCTAssertNotEqual(resolved, "Something went wrong on the server",
                          "Legacy English must not leak to the user")
        XCTAssertNotEqual(resolved, "api.error.server-generic",
                          "Fallback key should be resolved, not returned as-is")
    }

    // MARK: - APIError.userFacingMessage()

    func testAPIError_fixedCasesResolve() {
        let cases: [(APIError, String)] = [
            (.invalidURL, "api.error.invalid-url"),
            (.invalidResponse, "api.error.invalid-response"),
            (.decodingError(NSError(domain: "test", code: 1)), "api.error.decoding"),
            (.unauthorized, "api.error.unauthorized")
        ]
        for (error, expectedKey) in cases {
            let msg = error.userFacingMessage()
            XCTAssertFalse(msg.isEmpty, "\(error) produced empty message")
            XCTAssertNotEqual(msg, expectedKey,
                              "\(error) returned unresolved dot-key: \(msg)")
        }
    }

    func testAPIError_httpErrorDoesNotLeakStatusCode() {
        let fourHundred = APIError.httpError(statusCode: 404).userFacingMessage()
        let fiveHundred = APIError.httpError(statusCode: 500).userFacingMessage()
        XCTAssertFalse(fourHundred.contains("404"), "4xx leaked status: \(fourHundred)")
        XCTAssertFalse(fiveHundred.contains("500"), "5xx leaked status: \(fiveHundred)")
    }

    func testAPIError_serverErrorWithDotKeyResolves() {
        let msg = APIError.serverError(message: "discover.fetch-failed").userFacingMessage()
        XCTAssertNotEqual(msg, "discover.fetch-failed",
                          "serverError dot-key should be resolved, not returned as-is")
    }

    func testAPIError_serverErrorWithLegacyEnglishUsesFallback() {
        let msg = APIError.serverError(message: "Old English error").userFacingMessage()
        XCTAssertNotEqual(msg, "Old English error",
                          "Legacy English must not leak from serverError")
    }

    // MARK: - UserFacingAPIError

    func testUserFacingAPIError_cancellationReturnsEmpty() {
        let msg = UserFacingAPIError.message(for: CancellationError())
        XCTAssertEqual(msg, "", "CancellationError must produce empty UI message")
    }

    func testUserFacingAPIError_unwrapsTypedErrors() {
        let apiMsg = UserFacingAPIError.message(for: APIError.invalidURL)
        XCTAssertFalse(apiMsg.isEmpty)

        let authMsg = UserFacingAPIError.message(for: AuthError.invalidSeedPhrase)
        XCTAssertFalse(authMsg.isEmpty)

        let yrsMsg = UserFacingAPIError.message(for: YrsError.applyFailed(context: "test"))
        XCTAssertFalse(yrsMsg.isEmpty)
    }
}
