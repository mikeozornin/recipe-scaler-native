//
//  AuthErrorLocalizationTests.swift
//
//  MIK-163 — regression test for the `auth_error` UI-injection vulnerability:
//  the Socket.IO `auth_error` payload's raw `message` field used to be forwarded
//  verbatim into `ConnectionState.error(_)` and rendered in the trusted sync
//  banner via `connection.state.error` ("Sync error: %@"). A compromised server
//  or MITM on the sync channel could thus inject arbitrary text into the UI.
//
//  Contract under test:
//    1. The dedicated localization key `connection.state.auth-error` exists in
//       `Localizable.xcstrings` and resolves to a real translation (en + ru),
//       not the dot-key itself.
//    2. The legacy `connection.state.error` format string no longer leaks the
//       raw server detail when the auth_error path renders an `error` state —
//       the YjsSyncService handler passes a pre-localized string, so the `%@`
//       interpolation is fed a localized value, not server payload.
//

import XCTest
@testable import RecipeScalerNative

final class AuthErrorLocalizationTests: XCTestCase {

    // MARK: - connection.state.auth-error

    func test_authErrorKey_resolvesInBundle() {
        let resolved = Bundle.currentLocalizedString("connection.state.auth-error")
        XCTAssertFalse(resolved.isEmpty,
                      "connection.state.auth-error returned an empty string — key missing?")
        XCTAssertNotEqual(resolved, "connection.state.auth-error",
                         "Dot-key leaked verbatim — no translation in Localizable.xcstrings")
    }

    func test_authErrorKey_isNotParameterized() {
        // The auth_error path does not interpolate any server-supplied text,
        // so the key must NOT be a format string (no %@) — otherwise a future
        // change to YjsSyncService could reintroduce the injection vector.
        let resolved = Bundle.currentLocalizedString("connection.state.auth-error")
        XCTAssertFalse(resolved.contains("%@"),
                      "connection.state.auth-error contains a format specifier — " +
                      "the whole point of the fix is that no server text is interpolated")
    }

    func test_authErrorKey_neverContainsLegacyAuthFailureString() {
        // The previous code used the literal "Authentication failed" as a fallback
        // when the payload had no `message`. That English string must never appear
        // in the user-facing resolution.
        let resolved = Bundle.currentLocalizedString("connection.state.auth-error")
        XCTAssertFalse(resolved.contains("Authentication failed"),
                      "Legacy English 'Authentication failed' leaked: \(resolved)")
    }

    // MARK: - ConnectionState.displayLabel does not carry server payload

    func test_connectionStateError_displayLabel_carriesLocalizedNotRawInput() {
        // After MIK-163, YjsSyncService passes a pre-localized string (resolved
        // from connection.state.auth-error) into ConnectionState.error(_). The
        // state's displayLabel interpolates that value via connection.state.error
        // ("Sync error: %@"). This test pins the contract: the interpolated
        // string ends up in the label, but the *source* of the interpolation
        // is a localized value rather than raw server text.
        //
        // We cannot drive the live Socket.IO event from a unit test, so this
        // asserts the narrower contract that `ConnectionState.error(...)` still
        // works with a localized string as input — i.e. the fix did not break
        // the displayLabel path, and the chosen localized message round-trips
        // through the format string without leaking a dot-key.
        let localized = Bundle.currentLocalizedString("connection.state.auth-error")
        let state = ConnectionState.error(localized)
        let label = state.displayLabel

        XCTAssertFalse(label.isEmpty, "displayLabel returned an empty string")
        XCTAssertFalse(label.contains("connection.state."),
                      "displayLabel leaked a dot-key prefix: \(label)")
        XCTAssertTrue(label.contains(localized),
                     "displayLabel should embed the pre-localized auth-error message; got: \(label)")
    }
}
