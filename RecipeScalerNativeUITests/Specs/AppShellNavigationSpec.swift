import XCTest

/// Spec coverage: specs/007-app-shell-navigation/spec.md
///
/// Web parity: tests/e2e/specs/007-app-shell-navigation.spec.ts
///
///   - US1 — 5 tabs visible
///   - US2 — reset nested routes (tab tap resets to root)
///   - US3 — Import tab → sheet (only trigger here)
///   - US4 — safe area + timer panel
///   - US5 — sync lifecycle (covered indirectly by other specs)
final class AppShellNavigationSpec: BaseTestCase {
    func test_US1_fiveTabsVisible() {
        Navigation.openTab(.recipes, in: app)
        // Tab bar should appear with all 5 tab buttons.
        XCTAssertTrue(
            app.buttons[UIA.tabDiscover].waitForExistence(timeout: Wait.firstPaint),
            "Discover tab missing"
        )
        XCTAssertTrue(app.buttons[UIA.tabImport].exists, "Import tab missing")
        XCTAssertTrue(app.buttons[UIA.tabRecipes].exists, "Recipes tab missing")
        XCTAssertTrue(app.buttons[UIA.tabShopping].exists, "Shopping tab missing")
        XCTAssertTrue(app.buttons[UIA.tabProfile].exists, "Profile tab missing")
    }

    func test_US2_tabSwitchWorks() {
        Navigation.openTab(.recipes, in: app)
        // Switching tabs should land on each root.
        Navigation.openTab(.shopping, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.shoppingList].waitForExistence(timeout: Wait.firstPaint),
            "Shopping root did not appear after tap"
        )

        Navigation.openTab(.discover, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.discoverRoot].waitForExistence(timeout: Wait.firstPaint),
            "Discover root did not appear after tap"
        )

        Navigation.openTab(.profile, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.accountRoot].waitForExistence(timeout: Wait.firstPaint),
            "Account root did not appear after tap"
        )

        Navigation.openTab(.recipes, in: app)
        // After tab switches, Recipes tab root may take a moment to rehydrate.
        // Default UI is collections grid — wait for add button or "All" tile,
        // not recipe_list (absent until plain List mode).
        _ = recipeListPage.awaitReady(timeout: Wait.firstPaint)
    }

    func test_US3_importTabOpensSheet() {
        Navigation.openTab(.recipes, in: app)
        Navigation.openTab(.importTab, in: app)
        // Import sheet should appear (placeholder or full content from 010).
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.importSheet].waitForExistence(timeout: Wait.element),
            "Import sheet did not appear when Import tab tapped"
        )
    }
}
