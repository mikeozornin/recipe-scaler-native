import XCTest

/// Spec coverage: specs/045-public-image-cache/spec.md
///
/// Public-recipe image cache behavior. Caching is internal; this E2E
/// verifies the discover screen does not crash when rendering cached
/// public recipe cards.
final class PublicImageCacheSpec: BaseTestCase {
    func test_US1_discoverScreenRendersWithoutCrash() {
        Navigation.openTab(.discover, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.discoverRoot].waitForExistence(timeout: Wait.firstPaint),
            "Discover root did not render — image cache may have crashed"
        )
    }
}
