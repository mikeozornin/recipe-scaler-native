import XCTest
import UIKit

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

/// Regular-shell positive invariants for the iPad wide layout.
///
/// The same source is compiled into the iOS UI-test target as the existing
/// navigation spec, so this stays a runnable contract instead of a prose-only
/// claim in specs/062-mac-ipad-layout/plan.md.
final class RegularRecipesShellSpec: BaseTestCase {
    private var seededRecipe: SeedClient.CreatedRecipe?

    override func extraLaunchArguments() -> [String] {
        ["-ForceLayout=wide"]
    }

    override func prepareBeforeLaunch() async throws {
        seededRecipe = try await seedOrSkip("create regular-shell recipe") {
            try await seedClient.createRecipe(
                name: TestData.recipeName("Regular shell")
            )
        }
    }

    func test_regularShellUsesSystemSidebarWithoutBottomTabs() {
        revealSidebarIfNeeded()
        XCTAssertTrue(
            element(UIA.sidebarRecipes).waitForExistence(timeout: Wait.firstPaint),
            "Regular shell sidebar did not appear"
        )
        XCTAssertTrue(element(UIA.sidebarDiscover).exists, "Discover sidebar item missing")
        XCTAssertTrue(element(UIA.sidebarShopping).exists, "Shopping sidebar item missing")
        XCTAssertTrue(element(UIA.sidebarProfile).exists, "Profile sidebar item missing")
        XCTAssertFalse(
            element(UIA.tabRecipes).exists,
            "Regular shell must not expose compact bottom-tab chrome"
        )
    }

    func test_regularRecipeSelectionUsesDetailColumn() throws {
        revealSidebarIfNeeded()
        XCTAssertTrue(
            element(UIA.sidebarRecipes).waitForExistence(timeout: Wait.firstPaint),
            "Recipes sidebar item missing"
        )

        let seeded = try XCTUnwrap(seededRecipe)
        let list = recipeListPage.awaitReady()
        list.openAllRecipesIfNeeded()
        let firstRecipe = list.recipeRow(id: seeded.id)
        guard firstRecipe.waitForExistence(timeout: Wait.element) else {
            throw XCTSkip(
                "Seeded recipe did not reach the iPad collection list; "
                + "selection assertion requires a live Socket.IO sync transport"
            )
        }

        firstRecipe.tap()

        XCTAssertTrue(
            element(UIA.recipeDetailMenu).waitForExistence(timeout: Wait.firstPaint),
            "Selecting a regular recipe did not render the detail column"
        )
    }

    func test_regularRecipeKeepsTouchSwipeActions() throws {
        revealSidebarIfNeeded()
        XCTAssertTrue(
            element(UIA.sidebarRecipes).waitForExistence(timeout: Wait.firstPaint),
            "Recipes sidebar item missing"
        )

        let seeded = try XCTUnwrap(seededRecipe)
        let list = recipeListPage.awaitReady()
        list.openAllRecipesIfNeeded()
        let row = list.recipeRow(id: seeded.id)
        guard row.waitForExistence(timeout: Wait.element) else {
            throw XCTSkip(
                "Seeded recipe did not reach the iPad collection list; "
                + "touch-action assertion requires a live Socket.IO sync transport"
            )
        }

        row.swipeLeft()

        XCTAssertTrue(
            element(UIA.recipeRowDelete(id: seeded.id)).waitForExistence(timeout: Wait.element),
            "iPad regular recipe row did not reveal the touch trailing swipe action"
        )
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func revealSidebarIfNeeded() {
        let sidebar = element(UIA.sidebarRecipes)
        guard !sidebar.waitForExistence(timeout: 1) else { return }

        let showSidebar = app.buttons["Show Sidebar"].firstMatch
        XCTAssertTrue(
            showSidebar.waitForExistence(timeout: Wait.element),
            "System sidebar toggle did not appear"
        )
        if showSidebar.exists {
            showSidebar.tap()
        }
        XCTAssertTrue(
            sidebar.waitForExistence(timeout: Wait.element),
            "System sidebar did not open"
        )
    }
}

/// iPad regular keeps Shopping in the touch profile: deleting an item is
/// exposed by a finger swipe, never by a hover-only control.
final class RegularShoppingShellSpec: BaseTestCase {
    override func extraLaunchArguments() -> [String] {
        ["-ForceLayout=wide"]
    }

    func test_regularShoppingKeepsTouchDeleteAction() throws {
        revealSidebarIfNeeded()
        XCTAssertTrue(
            element(UIA.sidebarShopping).waitForExistence(timeout: Wait.firstPaint),
            "Shopping sidebar item missing"
        )
        element(UIA.sidebarShopping).tap()

        let label = "Regular shopping \(UUID().uuidString.prefix(8))"
        let addField = app.textFields[UIA.shoppingAddField]
        XCTAssertTrue(
            addField.waitForExistence(timeout: Wait.firstPaint),
            "Shopping add field missing in regular shell"
        )
        addField.tap()
        addField.typeText(label + "\n")

        let row = app.staticTexts[label]
        guard row.waitForExistence(timeout: Wait.element) else {
            throw XCTSkip(
                "Shopping item did not reach the iPad list; "
                + "touch-action assertion requires a live Socket.IO sync transport"
            )
        }

        row.swipeLeft()

        let deleteAction = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", UIA.shoppingItemDeletePrefix)
        ).firstMatch
        XCTAssertTrue(
            deleteAction.waitForExistence(timeout: Wait.element),
            "iPad regular shopping row did not reveal the touch trailing delete action"
        )
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func revealSidebarIfNeeded() {
        let sidebar = element(UIA.sidebarShopping)
        guard !sidebar.waitForExistence(timeout: 1) else { return }

        let showSidebar = app.buttons["Show Sidebar"].firstMatch
        XCTAssertTrue(
            showSidebar.waitForExistence(timeout: Wait.element),
            "System sidebar toggle did not appear"
        )
        if showSidebar.exists {
            showSidebar.tap()
        }
        XCTAssertTrue(
            sidebar.waitForExistence(timeout: Wait.element),
            "System sidebar did not open"
        )
    }
}

/// Backend-independent shell smoke. The app's DEBUG simulator session and
/// in-memory test container are enough to verify the platform chrome; recipe
/// selection remains covered by `RegularRecipesShellSpec`, which requires a
/// synced collection entry.
final class AdaptiveShellLocalSmokeSpec: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    func test_regularShellUsesSidebarWithoutBottomTabs() {
        launch(layout: "wide")
        revealSidebarIfNeeded()

        XCTAssertTrue(
            element(UIA.sidebarRecipes).waitForExistence(timeout: 10),
            "Regular shell sidebar did not appear without a backend"
        )
        XCTAssertTrue(element(UIA.sidebarDiscover).exists)
        XCTAssertTrue(element(UIA.sidebarShopping).exists)
        XCTAssertTrue(element(UIA.sidebarProfile).exists)
        XCTAssertFalse(
            element(UIA.tabRecipes).exists,
            "Regular shell must not expose compact bottom-tab chrome"
        )
    }

    func test_compactShellKeepsBottomTabsWithoutSidebar() {
        launch(layout: "compact")

        XCTAssertTrue(
            element(UIA.tabRecipes).waitForExistence(timeout: 10),
            "Compact shell bottom tabs did not appear without a backend"
        )
        for identifier in [UIA.tabDiscover, UIA.tabShopping, UIA.tabProfile] {
            XCTAssertTrue(
                element(identifier).waitForExistence(timeout: Wait.element),
                "Compact shell tab missing: \(identifier)"
            )
        }
        XCTAssertFalse(
            element(UIA.sidebarRecipes).exists,
            "Compact shell must not expose regular sidebar chrome"
        )
    }

    func test_regularSidebarRoutesToSurfacesWithoutBackend() {
        launch(layout: "wide")
        revealSidebarIfNeeded()

        XCTAssertTrue(
            element(UIA.sidebarDiscover).waitForExistence(timeout: Wait.firstPaint),
            "Discover sidebar item missing"
        )
        element(UIA.sidebarDiscover).tap()
        XCTAssertTrue(
            element(UIA.discoverRoot).waitForExistence(timeout: Wait.firstPaint),
            "Discover surface did not open from the regular sidebar"
        )

        XCTAssertTrue(element(UIA.sidebarShopping).waitForExistence(timeout: Wait.element))
        element(UIA.sidebarShopping).tap()
        revealSidebarIfNeeded()
        XCTAssertTrue(
            element(UIA.shoppingList).waitForExistence(timeout: Wait.firstPaint),
            "Shopping surface did not open from the regular sidebar"
        )

        XCTAssertTrue(element(UIA.sidebarProfile).waitForExistence(timeout: Wait.element))
        element(UIA.sidebarProfile).tap()
        revealSidebarIfNeeded()
        XCTAssertTrue(
            element(UIA.accountRoot).waitForExistence(timeout: Wait.firstPaint),
            "Profile surface did not open from the regular sidebar"
        )

        XCTAssertTrue(element(UIA.sidebarImport).waitForExistence(timeout: Wait.element))
        element(UIA.sidebarImport).tap()
        XCTAssertTrue(
            element(UIA.importSheet).waitForExistence(timeout: Wait.element),
            "Import sheet did not open from the regular sidebar"
        )
    }

    func test_regularAssistantUsesToolbarWithoutCompactFab() {
        launch(layout: "wide")

        let assistantToolbar = app.buttons[UIA.assistantToolbarButton].firstMatch
        XCTAssertTrue(
            assistantToolbar.waitForExistence(timeout: Wait.firstPaint),
            "Regular shell assistant toolbar action did not appear"
        )
        XCTAssertFalse(
            element(UIA.assistantFab).exists,
            "Regular shell must not expose the compact assistant FAB"
        )

        assistantToolbar.tap()
        XCTAssertTrue(
            element(UIA.assistantSheet).waitForExistence(timeout: Wait.element),
            "Regular shell assistant toolbar action did not present the assistant sheet"
        )
    }

    private func launch(layout: String) {
        // The regular iPad contract is the landscape three-column shell. In
        // portrait, NavigationSplitView is allowed to collapse the sidebar
        // even when the app is forced into the regular layout mode.
        XCUIDevice.shared.orientation = layout == "wide" ? .landscapeLeft : .portrait
        app.launchArguments = [
            "-SkipSplash=1",
            "-ForceLayout=\(layout)",
        ]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func revealSidebarIfNeeded() {
        let sidebar = element(UIA.sidebarDiscover)
        guard !sidebar.waitForExistence(timeout: 1) else { return }

        let showSidebar = app.buttons["Show Sidebar"].firstMatch
        XCTAssertTrue(
            showSidebar.waitForExistence(timeout: Wait.element),
            "System sidebar toggle did not appear"
        )
        if showSidebar.exists {
            showSidebar.tap()
        }
        XCTAssertTrue(
            sidebar.waitForExistence(timeout: Wait.element),
            "System sidebar did not open"
        )
    }
}
