import XCTest

/// Spec coverage: specs/011-discover/spec.md
///
/// Web parity: tests/e2e/specs/011-discover-public.spec.ts
///
///   - US1 — Discover root renders with cards
///   - US2 — Search field present (soft-skip when feed has no search UI)
///   - US3 — Public collection/profile cards visible (depends on server content)
final class DiscoverPublicSpec: BaseTestCase {
    func test_US1_discoverRootRenders() {
        Navigation.openTab(.discover, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.discoverRoot].waitForExistence(timeout: Wait.firstPaint),
            "Discover root did not render"
        )
    }

    func test_US2_searchFieldPresent() throws {
        Navigation.openTab(.discover, in: app)
        _ = discoverPage.awaitReady()
        // Search field is rendered only when content exists. For a fresh
        // empty user the discover feed may legitimately have no search UI —
        // this is genuinely env-dependent (server content), so keep the
        // soft-skip here. NOT a regression. See review finding Critical #5
        // (env-conditional skips are legitimate; UI-a11y-id-missing skips
        // are not — DiscoverPublicSpec is the former).
        let collectionSearch = discoverPage.collectionSearchField.waitForExistence(timeout: Wait.element)
        let profileSearch = discoverPage.profileSearchField.exists
        try XCTSkipIf(
            !(collectionSearch || profileSearch),
            "No discover search field — feed has no public content for fresh user (env-conditional)"
        )
    }
}
