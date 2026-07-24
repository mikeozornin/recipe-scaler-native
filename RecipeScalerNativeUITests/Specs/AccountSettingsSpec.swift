import XCTest

/// Spec coverage: specs/013-account-settings/spec.md
///
/// Web parity: tests/e2e/specs/013-account-settings.spec.ts
///
///   - US1 — Profile/Account root renders
///   - US2 — Timer notifications toggle (soft-skip if UI not wired yet)
///   - US3 — Language switch (delegated to 022)
final class AccountSettingsSpec: BaseTestCase {
    func test_US1_accountRootVisible() {
        Navigation.openTab(.profile, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.accountRoot].waitForExistence(timeout: Wait.firstPaint),
            "Account root did not render"
        )
    }

    func test_US2_timerNotificationsTogglePresent() throws {
        Navigation.openTab(.profile, in: app)
        _ = accountPage.awaitReady()

        // Identifier is catalogued; AccountView must apply it. Absence is a
        // regression, not a soft-skip — fail so missing wiring surfaces in
        // CI. See review finding Critical #5.
        let toggle = app.descendants(matching: .any)[UIA.accountTimerNotificationsToggle]
        if !toggle.waitForExistence(timeout: Wait.element) {
            let scroll = app.scrollViews.firstMatch
            if scroll.exists { scroll.swipeUp() }
            if !toggle.waitForExistence(timeout: Wait.element) {
                let other = app.collectionViews.firstMatch
                if other.exists { other.swipeUp() }
            }
        }
        XCTAssertTrue(
            toggle.waitForExistence(timeout: Wait.element),
            "account_timer_notifications_toggle not in UI — wire the identifier on AccountView"
        )
    }
}
