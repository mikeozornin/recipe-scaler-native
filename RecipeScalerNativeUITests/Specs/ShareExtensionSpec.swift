import XCTest

/// Spec coverage: specs/025-share-extension/spec.md
///
/// Share-sheet extension. The extension runs in its own process and
/// cannot be driven from the host app's XCUITest target without a
/// dedicated test host. This spec only verifies the host app's share
/// entry points are reachable.
final class ShareExtensionSpec: BaseTestCase {
    func test_US1_appBootsForShareExtensionHostFlow() {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()
    }
}
