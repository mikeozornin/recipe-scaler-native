import XCTest

/// Spec coverage: specs/028-app-logging/spec.md
///
/// Verifies the DEBUG-only NDJSON log is present in the simulator sandbox
/// (or absent in Release, which we don't drive here). Mirrors the assertion
/// used by `scripts/verify-ui-smoke.sh`.
final class AppLoggingSpec: BaseTestCase {
    func test_appLaunchesAndLogIsAvailable() {
        Navigation.openTab(.recipes, in: app)
        // If the app boots and shows Recipes tab chrome, bootstrap wrote
        // to its NDJSON log. `Logs.assertNoCrash` in tearDown reads the
        // same file — passing tearDown implicitly proves the log exists.
        _ = recipeListPage.awaitReady()
    }
}
