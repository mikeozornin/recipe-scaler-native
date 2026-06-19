//
//  ErrorLocalizationTests.swift
//
//  Spec 031 — verifies the error-localization pipeline:
//    1. `DotKeyLocalizer.looksLikeDotKey` correctly classifies messages.
//    2. `DotKeyLocalizer.localize` resolves dot-keys via the runtime bundle,
//       and falls back to a generic key for legacy English strings.
//    3. `ServerErrorCode.from(serverValue:fallback:)` collapses unknown / legacy
//       server strings into a known fallback code.
//    4. `APIError.userFacingMessage()` resolves all cases without leaking
//       raw status codes or server-supplied English.
//    5. `UserFacingAPIError.message(for:)` returns "" for CancellationError
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

    // MARK: - ServerErrorCode

    func testServerErrorCode_rawValuesMatchDotKeyContract() {
        // Every case's rawValue must satisfy the dot-key regex — otherwise
        // `Bundle.currentLocalizedString(code.rawValue)` would not resolve.
        for code in ServerErrorCode.allCases {
            XCTAssertTrue(
                DotKeyLocalizer.looksLikeDotKey(code.rawValue),
                "ServerErrorCode.\(code) rawValue '\(code.rawValue)' is not a dot-key"
            )
        }
    }

    func testServerErrorCode_from_acceptsKnownDotKey() {
        let code = ServerErrorCode.from(
            serverValue: "assistant.threads.create.failed",
            fallback: .apiErrorServerGeneric
        )
        XCTAssertEqual(code, .assistantThreadsCreateFailed)
    }

    func testServerErrorCode_from_rejectsLegacyEnglishAndUsesFallback() {
        let code = ServerErrorCode.from(
            serverValue: "Profile load failed",
            fallback: .accountProfileLoadFailed
        )
        XCTAssertEqual(code, .accountProfileLoadFailed,
                       "Legacy English must collapse into the endpoint fallback")
    }

    func testServerErrorCode_from_handlesNilAndEmpty() {
        XCTAssertEqual(
            ServerErrorCode.from(serverValue: nil, fallback: .discoverFetchFailed),
            .discoverFetchFailed
        )
        XCTAssertEqual(
            ServerErrorCode.from(serverValue: "", fallback: .discoverFetchFailed),
            .discoverFetchFailed
        )
        XCTAssertEqual(
            ServerErrorCode.from(serverValue: "   ", fallback: .discoverFetchFailed),
            .discoverFetchFailed
        )
    }

    func testServerErrorCode_from_rejectsUnknownDotKey() {
        // A syntactically-valid dot-key that is NOT in the enum should fall back —
        // otherwise an unknown server code would silently resolve to the raw key.
        let code = ServerErrorCode.from(
            serverValue: "unknown.future.endpoint.failed",
            fallback: .apiErrorServerGeneric
        )
        XCTAssertEqual(code, .apiErrorServerGeneric,
                       "Unknown dot-key must collapse into the endpoint fallback")
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

    func testAPIError_serverErrorWithTypedCodeResolves() {
        let msg = APIError.serverError(code: .discoverFetchFailed).userFacingMessage()
        XCTAssertNotEqual(msg, "discover.fetch-failed",
                          "serverError code rawValue should be resolved, not returned as-is")
    }

    func testAPIError_serverErrorNeverLeaksRawDotKey() {
        // After the typed-code migration there is no way for English to leak
        // through `serverError` — `ServerErrorCode.from(...fallback:)` collapses
        // unknown / legacy strings into a known fallback at the throw-site, so
        // `userFacingMessage()` always receives a valid dot-key. The one thing
        // we still want to assert is that the bundle actually resolves it
        // (i.e. the rawValue is not returned verbatim, which would indicate a
        // missing key in `Localizable.xcstrings`).
        for code in ServerErrorCode.allCases {
            let msg = APIError.serverError(code: code).userFacingMessage()
            XCTAssertFalse(msg.isEmpty,
                           "Empty message for \(code)")
            XCTAssertNotEqual(msg, code.rawValue,
                              "Raw dot-key returned for \(code): key missing in Localizable.xcstrings")
        }
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
