import XCTest

/// Spec coverage: specs/014-timers-sync/spec.md
///
/// Web parity: tests/e2e/specs/014-timers-sync.spec.ts (two-context
/// collaboration). On native, multi-context realtime requires multiple
/// `XCUIApplication` instances — covered here in a simplified form that
/// verifies a REST-seeded timer shows up in the panel.
final class TimersSyncSpec: BaseTestCase {
    /// A REST-seeded running timer should be visible via the mobile timer panel.
    /// This is a one-way assertion (server → app); cross-device broadcast
    /// is exercised manually and via integration tests on staging.
    @MainActor
    func test_US1_seededRunningTimerBecomesVisible() async throws {
        Navigation.openTab(.recipes, in: app)
        let timerName = TestData.recipeName("Timer 014")
        _ = try await seedOrSkip("startTimer") {
            try await seedClient.startTimer(name: timerName, durationSec: 600)
        }

        // Open the mobile timer panel if it isn't already visible.
        // The panel toggles via a header tap on the recipes tab.
        let panel = app.descendants(matching: .any)[UIA.mobileTimerPanel]
        if !panel.exists {
            let header = app.descendants(matching: .any)[UIA.mobileTimerPanelHeader]
            if header.waitForExistence(timeout: Wait.element) {
                header.tap()
            }
        }

        // The chip may use the timerId (deterministic) or be looked up by name.
        let byName = app.otherElements.containing(
            NSPredicate(format: "label CONTAINS %@", timerName)
        ).firstMatch
        XCTAssertTrue(
            byName.waitForExistence(timeout: Wait.syncRoundTrip),
            "REST-seeded timer '\(timerName)' did not appear in mobile timer panel"
        )
    }
}
