import XCTest

/// Spec coverage: specs/036-timer-notification-actions/spec.md
///
/// Notification-tap → action. Real local notifications cannot be reliably
/// driven from XCUITest (system-level interception); this spec verifies
/// the timer panel renders and the seeded timer is interactable.
final class TimerNotificationActionsSpec: BaseTestCase {
    @MainActor
    func test_US1_timerPanelAccessibleAfterSeed() async throws {
        Navigation.openTab(.recipes, in: app)
        _ = try await seedOrSkip("startTimer") {
            try await seedClient.startTimer(name: TestData.recipeName("Notif 036"), durationSec: 60)
        }

        _ = recipeListPage.awaitReady()

        // The mobile timer panel appears at the top of the recipes screen
        // when there are active timers.
        let panel = app.descendants(matching: .any)[UIA.mobileTimerPanel]
        XCTAssertTrue(
            panel.waitForExistence(timeout: Wait.syncRoundTrip),
            "Timer panel did not appear after seeding a running timer"
        )
    }
}
