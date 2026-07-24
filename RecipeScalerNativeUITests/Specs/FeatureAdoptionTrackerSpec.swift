import XCTest

/// Spec coverage: specs/038-feature-adoption-tracker/spec.md
///
/// Feature-adoption tracking: which features the user has used at least
/// once. The tracker is internal; this E2E verifies the app boots without
/// crashing when adoption state is fresh (after reset).
final class FeatureAdoptionTrackerSpec: BaseTestCase {
    func test_US1_appBootsAfterAdoptionCacheReset() {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()
    }
}
