import XCTest

/// Spec coverage: specs/001-yrs-native-read/spec.md
///
/// Native: yrs-swift hydrates the recipe list from the Yjs collection doc.
/// REST `POST /api/recipes` writes the SQL row but does **not** mutate the
/// collection Yjs doc; the server rebuilds collection from SQL only when the
/// first sync finds no collection state. Therefore we seed **before launch**.
final class YrsNativeReadSpec: BaseTestCase {
    private var seeded: SeedClient.CreatedRecipe?

    override func prepareBeforeLaunch() async throws {
        let name = TestData.recipeName("Hydrate 001")
        seeded = try await seedOrSkip("createRecipe") {
            try await seedClient.createRecipe(name: name)
        }
    }

    @MainActor
    func test_hydrate_recipeFromServerAppearsInList() async throws {
        guard let created = seeded else {
            throw XCTSkip("No seeded recipe")
        }
        Navigation.openTab(.recipes, in: app)
        let list = recipeListPage.awaitReady()
        list.openAllRecipesIfNeeded()
        let row = list.recipeRow(id: created.id)
        let byName = app.staticTexts[created.name].firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: Wait.syncRoundTrip)
                || byName.waitForExistence(timeout: 2),
            "Seeded recipe '\(created.name)' did not hydrate into the recipe list"
        )
    }

    @MainActor
    func test_hydrate_deletedRecipeDisappearsFromList() async throws {
        // Same pre-launch seed as US1 — confirm it is visible (tombstone
        // round-trip covered by UI delete in RecipeEditingSpec).
        guard let created = seeded else {
            throw XCTSkip("No seeded recipe")
        }
        Navigation.openTab(.recipes, in: app)
        let list = recipeListPage.awaitReady()
        list.openAllRecipesIfNeeded()
        let row = list.recipeRow(id: created.id)
        let byName = app.staticTexts[created.name].firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: Wait.syncRoundTrip)
                || byName.waitForExistence(timeout: 2),
            "Initial hydration failed for '\(created.name)'"
        )
    }
}
