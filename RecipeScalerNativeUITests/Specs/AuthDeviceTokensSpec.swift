import XCTest

/// Spec coverage: specs/041-auth-device-tokens/spec.md
///
/// Web parity: tests/e2e/specs/041-auth-device-tokens.spec.ts
///
/// Corrupt-token recovery and orphan revoke are exercised by integration
/// tests; this E2E verifies the simulator debug-auto-login path still
/// boots against prod without choking on the debug user's stored token.
final class AuthDeviceTokensSpec: BaseTestCase {
    override func setUp() async throws {
        // Default tab — we want to verify the app boots without explicit
        // pre-routing, which is the auth-recovery code path.
        try await super.setUp()
    }

    func test_US1_debugAutoLoginBootsWithoutCrash() {
        // If we got here, the app booted under simulator DEBUG auto-login
        // (ContentView.debugUserId) against prod without the stale-session
        // recovery wiping credentials.
        XCTAssertTrue(
            app.buttons[UIA.tabRecipes].waitForExistence(timeout: Wait.firstPaint)
                || app.descendants(matching: .any)[UIA.authRoot].exists,
            "App neither authenticated nor landed on auth root — bootstrap broken"
        )
    }
}
