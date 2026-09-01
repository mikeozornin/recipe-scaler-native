import XCTest

/// Spec coverage: specs/015-assistant/spec.md, specs/074-assistant-tab-entry/spec.md
///
/// Web parity: tests/e2e/specs/015-assistant.spec.ts (launcher + draft restore).
///
/// Native (spec 074): the assistant opens from the tab-bar button (fake tab);
/// the sheet presents over the current tab and the tab selection never changes.
final class AssistantSpec: BaseTestCase {
    func test_US1_assistantTabVisible() throws {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()
        let tabButton = assistantPage.tabButton
        XCTAssertTrue(
            tabButton.waitForExistence(timeout: Wait.firstPaint),
            "Assistant tab button not found by id/label — assistant wiring regressed"
        )
    }

    func test_US2_openingAssistantTabShowsSheet() throws {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()
        let page = assistantPage
        XCTAssertTrue(
            page.tabButton.waitForExistence(timeout: Wait.element),
            "Assistant tab button not found by id/label — assistant wiring regressed"
        )
        page.tabButton.tap()
        XCTAssertTrue(
            page.sheet.waitForExistence(timeout: Wait.element),
            "Assistant sheet did not appear after assistant tab tap"
        )
    }

    /// Spec 074 PI-3 — after dismissing the sheet (swipe down), tapping the
    /// assistant tab again must re-open it (the tab-open flag resets on
    /// consumption, so a stale presentation state must not block re-entry).
    func test_US3_reopeningAssistantAfterDismissShowsSheetAgain() throws {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()
        let page = assistantPage

        page.openViaTab().awaitSheet()
        page.dismissViaSwipe()

        XCTAssertTrue(
            page.tabButton.waitForExistence(timeout: Wait.element),
            "Assistant tab button missing after sheet dismiss"
        )
        page.openViaTab().awaitSheet()
    }
}

/// Repro for iOS 26 toolbar env crash: assistant dismiss → recipe detail push.
///
/// XCTest uses **register-auto + REST seed** (same toolbar/nav path as manual repro).
/// Prod debug-user + full bootstrap: `bash scripts/repro-assistant-recipe-crash.sh`.
///
/// **Phase 1:** detail must open after assistant dismiss → recipe tap (else crash/no push).
/// **Phase 2:** app stays `runningForeground` (`Logs.assertNoCrash` in tearDown).
final class AssistantRecipeNavReproSpec: BaseTestCase {
    private var seededRecipeId: String?

    override func extraLaunchArguments() -> [String] { ["-OpenTab=recipes"] }

    override func prepareBeforeLaunch() async throws {
        let name = "NavRepro \(UUID().uuidString.prefix(6))"
        let created = try await seedOrSkip("createRecipe") {
            try await seedClient.createRecipe(name: name)
        }
        seededRecipeId = created.id
    }

    func test_assistantDismissThenOpenRecipe_survivesNavigation() throws {
        executionTimeAllowance = 180

        var list = recipeListPage.awaitReady()
        list.openAllRecipesIfNeeded()

        guard let recipeId = seededRecipeId else {
            XCTFail("prepareBeforeLaunch did not set seededRecipeId")
            return
        }

        let row = list.recipeRow(id: recipeId)
        XCTAssertTrue(
            row.waitForExistence(timeout: Wait.syncRoundTrip)
                || list.hasRecipes,
            "Seeded recipe \(recipeId) did not appear — cannot exercise assistant→detail nav"
        )

        assistantPage.openViaTab().awaitSheet()
        assistantPage.dismissViaSwipe()

        list = recipeListPage.awaitReady(timeout: Wait.element)
        list.openAllRecipesIfNeeded()

        list.tapFirstRecipe()

        let detailVisible = recipeDetailPage.menuButton.waitForExistence(timeout: Wait.syncRoundTrip)
            || recipeDetailPage.ingredientsSection.waitForExistence(timeout: Wait.element)
            || recipeDetailPage.editButton.waitForExistence(timeout: Wait.element)
        XCTAssertTrue(
            detailVisible,
            "Recipe detail did not open — navigation push (toolbar env crash) was not exercised"
        )

        XCTAssertEqual(
            app.state,
            .runningForeground,
            "App crashed after opening recipe detail"
        )
    }
}
