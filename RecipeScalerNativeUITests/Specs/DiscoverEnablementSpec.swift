import XCTest

/// Spec coverage: specs/017-discover-enablement/spec.md
///
/// Feature flag for the Discover tab. When enabled, the Discover tab
/// is visible in the shell. When disabled, it is hidden. Production
/// builds enable Discover; this E2E verifies the tab is present.
final class DiscoverEnablementSpec: BaseTestCase {
    override func setUp() async throws {
        try await super.setUp()
    }

    func test_US1_discoverTabPresentWhenEnabled() {
        XCTAssertTrue(
            app.buttons[UIA.tabDiscover].waitForExistence(timeout: Wait.firstPaint),
            "Discover tab missing — feature flag may be off in this build"
        )
    }
}
