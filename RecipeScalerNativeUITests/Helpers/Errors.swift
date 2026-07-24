import Foundation

/// Errors raised by E2E fixtures (REST seeding, reset, auth registration).
///
/// Conforms to `LocalizedError` so `XCTSkip` / `XCTFail` messages render the
/// full description in test logs and `.xcresult` bundles — default
/// `CustomStringConvertible` conformance is invisible to XCTest's
/// error-reporting path. See review finding Standards #32.
enum E2EError: Error, LocalizedError {
    case nonHTTPResponse
    case unexpectedStatus(String, Int)

    var errorDescription: String? {
        switch self {
        case .nonHTTPResponse:
            return "E2EError: non-HTTP response"
        case .unexpectedStatus(let label, _):
            // `label` already includes status + truncated response body from ensureOK.
            return "E2EError: \(label)"
        }
    }

    var description: String {
        errorDescription ?? "E2EError"
    }
}
