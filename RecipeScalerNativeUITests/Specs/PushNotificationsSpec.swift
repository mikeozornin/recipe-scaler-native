import XCTest

/// Spec coverage: specs/023-push-notifications/spec.md
///
/// Web parity: tests/e2e/specs/023-push-notifications.spec.ts
///
/// Permission prompt + APNs registration. The actual permission dialog
/// cannot be driven reliably from XCUITest (system alert blockers), so
/// this spec verifies the account-screen toggle for timer notifications
/// when present. Soft-skips if the toggle identifier is not wired in Views.
final class PushNotificationsSpec: BaseTestCase {
    func test_US1_timerNotificationsToggleTappable() throws {
        Navigation.openTab(.profile, in: app)
        let page = accountPage.awaitReady()
        let toggle = app.descendants(matching: .any)[UIA.accountTimerNotificationsToggle]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: Wait.element),
            "account_timer_notifications_toggle not in UI — wire the identifier on AccountView"
        )
        // Prefer page accessor if typed as button; fall back to descendants.
        let target = page.timerNotificationsToggle.exists ? page.timerNotificationsToggle : toggle
        XCTAssertTrue(target.isHittable, "Toggle not hittable")
    }
}
