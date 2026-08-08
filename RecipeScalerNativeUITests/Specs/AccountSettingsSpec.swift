import XCTest

/// Spec coverage: specs/013-account-settings/spec.md + specs/055-account-deletion/spec.md
///
/// Web parity: tests/e2e/specs/013-account-settings.spec.ts
///
///   - US1 — Profile/Account root renders
///   - US2 — Timer notifications toggle (soft-skip if UI not wired yet)
///   - US3 — Language switch (delegated to 022)
///   - 055 — Account deletion (cancel warning / cancel seed / full delete)
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

    func test_US4_tipsSectionVisible() {
        Navigation.openTab(.profile, in: app)
        _ = accountPage.awaitReady()

        let tips = app.descendants(matching: .any)[UIA.accountTipsSection]
        if !tips.waitForExistence(timeout: Wait.element) {
            if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            } else if app.collectionViews.firstMatch.exists {
                app.collectionViews.firstMatch.swipeUp()
            }
        }

        XCTAssertTrue(
            tips.waitForExistence(timeout: Wait.element),
            "account_tips_section not in UI — wire Tips into AccountView"
        )

        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.accountTipsMenu].waitForExistence(timeout: Wait.element),
            "account_tips_menu not in UI — tips should be opened as a submenu"
        )
    }

    // MARK: - Spec 055 — Account deletion

    /// UITest runner has no Localizable.xcstrings — system alert labels are EN.
    private let deleteWarningCancelLabel = "Cancel"
    private let deleteWarningContinueLabel = "Continue"

    /// Step 1 (warning) → Cancel keeps the account intact.
    func test_055_cancelOnWarningKeepsAccount() throws {
        Navigation.openTab(.profile, in: app)
        _ = accountPage.awaitReady()

        let deleteButton = accountPage.revealDeleteAccount()
        XCTAssertTrue(deleteButton.waitForExistence(timeout: Wait.element))
        deleteButton.tap()

        // SwiftUI `.alert` renders system buttons without accessibility ids —
        // resolve by EN label (UITest bundle has no string catalog).
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: Wait.element))
        alert.buttons[deleteWarningCancelLabel].tap()

        // Account still here; no seed sheet was presented.
        XCTAssertFalse(accountPage.deleteAccountSeedInput.exists)
        XCTAssertTrue(accountPage.root.exists)
    }

    /// Step 1 (warning) → Continue → Step 2 seed → Cancel returns without deleting.
    func test_055_cancelOnSeedStepKeepsAccount() throws {
        Navigation.openTab(.profile, in: app)
        _ = accountPage.awaitReady()

        let deleteButton = accountPage.revealDeleteAccount()
        deleteButton.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: Wait.element))
        alert.buttons[deleteWarningContinueLabel].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: Wait.element))

        let seedInput = accountPage.deleteAccountSeedInput
        let cancel = accountPage.deleteAccountCancelButton
        // Sheet opens after alert onChange — wait for stable chrome (input + cancel).
        XCTAssertTrue(
            seedInput.waitForExistence(timeout: Wait.element * 2),
            "Seed sheet did not appear after Continue"
        )
        XCTAssertTrue(
            cancel.waitForExistence(timeout: Wait.element),
            "Seed sheet Cancel control missing"
        )
        cancel.tap()
        XCTAssertTrue(
            seedInput.waitForNonExistence(timeout: Wait.element),
            "Seed sheet should dismiss after Cancel"
        )
        XCTAssertTrue(accountPage.root.exists)
    }

    /// Full flow: warning → seed → confirm hits the server; Danger Zone gone.
    /// Under `E2E_OVERRIDE_USER_ID` ContentView keeps the shell (no authRoot).
    func test_055_fullDeleteFlow() throws {
        Navigation.openTab(.profile, in: app)
        _ = accountPage.awaitReady()

        let seed = e2eUser.seedPhrase
        XCTAssertFalse(seed.isEmpty, "No registered seed phrase for delete-account test")

        let deleteButton = accountPage.revealDeleteAccount()
        deleteButton.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: Wait.element))
        alert.buttons[deleteWarningContinueLabel].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: Wait.element))

        let seedInput = accountPage.deleteAccountSeedInput
        XCTAssertTrue(
            seedInput.waitForExistence(timeout: Wait.element * 2),
            "Seed sheet did not appear after Continue"
        )
        XCTAssertTrue(
            accountPage.deleteAccountCancelButton.waitForExistence(timeout: Wait.element),
            "Seed sheet Cancel control missing"
        )
        // Prefer paste over typeText — SwiftUI TextEditor in sheets often fails hit-testing.
        UIPasteboard.general.string = seed
        seedInput.tap()
        seedInput.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"]
        if paste.waitForExistence(timeout: 3) {
            paste.tap()
        } else {
            seedInput.typeText(seed)
        }

        let confirm = accountPage.deleteAccountConfirmButton
        XCTAssertTrue(confirm.waitForExistence(timeout: Wait.element))
        // Confirm enables once 12 words are present — wait briefly for binding.
        let enabledDeadline = Date().addingTimeInterval(Wait.element)
        while !confirm.isEnabled, Date() < enabledDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(confirm.isEnabled, "Confirm should be enabled with 12-word seed")
        confirm.tap()

        // Sheet dismisses on success; Danger Zone hides when authService.isAuthenticated
        // flips false. E2E override keeps the app shell (not authRoot), but Account may
        // briefly rebuild after wipe — wait for tab chrome, then re-open Profile.
        XCTAssertTrue(
            seedInput.waitForNonExistence(timeout: Wait.element),
            "Seed sheet should dismiss after successful deletion"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.tabProfile].waitForExistence(timeout: Wait.element),
            "App shell (Profile tab) should remain under E2E override"
        )
        Navigation.openTab(.profile, in: app)
        _ = accountPage.awaitReady()
        // Danger Zone is gated on authService.isAuthenticated — gone after wipe.
        // Scroll in case the list restored mid-fold.
        _ = accountPage.revealDeleteAccount()
        XCTAssertTrue(
            accountPage.deleteAccountButton.waitForNonExistence(timeout: Wait.element),
            "Danger Zone delete button should disappear after account deletion"
        )
    }
}
