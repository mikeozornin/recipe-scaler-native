import XCTest

/// Spec coverage: specs/054-auth-stale-session-recovery/spec.md
///
/// Web parity: tests/e2e/specs/054-auth-stale-session-recovery.spec.ts
///
/// Stale-session recovery (when server wipes the user but client still
/// has credentials) is exercised by integration tests. This E2E verifies
/// the app boots without throwing under the default debug-auto-login.
final class AuthStaleSessionRecoverySpec: BaseTestCase {
    override func setUp() async throws {
        try await super.setUp()
    }

    func test_US1_appBootsToAuthenticatedState() {
        // Reaching the tab bar implies `bootstrap` completed the
        // stale-session health check (spec 054) successfully for the
        // debug user.
        XCTAssertTrue(
            app.buttons[UIA.tabRecipes].waitForExistence(timeout: Wait.firstPaint),
            "App did not reach authenticated tab bar — stale-session check may have failed"
        )
    }
}
