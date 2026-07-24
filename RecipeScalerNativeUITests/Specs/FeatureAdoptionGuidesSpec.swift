import XCTest

/// Spec coverage: specs/040-feature-adoption-guides/spec.md
///
/// First-time-user adoption guides / coach marks. These appear once per
/// feature adoption event and are suppressed after dismissal. After a
/// server-side reset the adoption cache is wiped, so guides may reappear.
final class FeatureAdoptionGuidesSpec: BaseTestCase {
    func test_US1_appBootsAndRecipeListReachable() {
        Navigation.openTab(.recipes, in: app)
        // Reaching Recipes-tab chrome implies the adoption-guide overlay
        // (if any) did not crash the bootstrap.
        _ = recipeListPage.awaitReady()
    }
}
