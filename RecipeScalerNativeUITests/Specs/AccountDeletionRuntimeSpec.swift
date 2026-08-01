import XCTest

/// Spec coverage: specs/055-account-deletion/spec.md — Phase R (runtime recovery).
///
/// Web parity: tests/e2e/specs/045-account-deletion.spec.ts (peer-wipe fixture).
///
/// Phase R adds runtime recovery when the account is deleted **on another
/// device / on the server directly** while the native client is running.
/// Verifying the full peer-wipe path requires a server-side fixture to emit
/// `auth_error` "Account deleted" or to CASCADE-delete the user row mid-test,
/// which is not wired into the current E2E harness. The unit suite
/// `AuthSessionInvalidationTests` covers the recovery logic itself (5
/// positive invariants, mock-injected).
///
/// This E2E is a smoke check: app still boots to the authenticated tab bar
/// after Phase R wiring is in place — i.e. the new
/// `APIClient.unauthorizedHandler` + `sync.authInvalidationHandler`
/// installed from `AppContainer.init` did not break cold start.
final class AccountDeletionRuntimeSpec: BaseTestCase {
    override func setUp() async throws {
        try await super.setUp()
    }

    /// Smoke: app boots, new Phase R interceptors are wired (no crashes),
    /// and the user lands on the authenticated tab bar.
    func test_R1_appBootsToAuthenticatedStateWithRuntimeInterceptors() {
        XCTAssertTrue(
            app.buttons[UIA.tabRecipes].waitForExistence(timeout: Wait.firstPaint),
            "App did not reach authenticated tab bar — runtime interceptors may have broken bootstrap"
        )
    }
}
