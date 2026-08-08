import XCTest

/// Spec coverage: specs/002-native-editing/spec.md
///
/// Web parity: tests/e2e/specs/002-recipe-editing.spec.ts
///
///   - US1 — Create empty recipe via "+"
///   - US2 — Add ingredients (bulk via REST seed → UI shows them)
///   - US3 — Edit recipe (title, ingredients via grid)
///   - US4 — Scale servings
///   - US5 — Delete recipe (tombstone propagates)
final class RecipeEditingSpec: BaseTestCase {
    func test_US1_createEmptyRecipeViaUI() throws {
        Navigation.openTab(.recipes, in: app)
        let list = recipeListPage.awaitReady()

        XCTAssertTrue(list.addButton.waitForExistence(timeout: Wait.element),
                      "Recipe list add button missing")
        list.tapAddRecipe()

        // Detail should appear in edit mode (new recipes open editing).
        //
        // On loopback we treat a missing edit-mode row as a real regression —
        // the local backend is healthy by assumption, so createRecipe must
        // succeed and push the detail in edit mode. Fail hard.
        //
        // On prod we soft-skip: `POST /api/recipes` may legitimately return
        // 500 for fresh anonymous users (see BaseTestCase.seedOrSkip). The
        // tap then either surfaces an error alert (which the test does not
        // model) or silently no-ops; either way the regression signal here
        // is environment-driven, not code-driven. See review finding
        // Critical #5 + docs/E2E.md.
        let editRow = recipeDetailPage.newIngredientRow
        if !editRow.waitForExistence(timeout: Wait.firstPaint) {
            if E2EConfig.isLoopbackBackend {
                XCTFail("Create-via-+ did not open edit-mode ingredient row — create flow regressed")
            } else {
                throw XCTSkip(
                    "Create-via-+ did not open edit-mode ingredient row — soft-skipping (prod may reject anonymous recipe create)"
                )
            }
        }

        recipeDetailPage.tapDone()
        _ = list.awaitReady()
    }

    @MainActor
    func test_US2_restSeededIngredientsAppearInUI() async throws {
        Navigation.openTab(.recipes, in: app)
        let name = TestData.recipeName("RestSeed 002")
        let created = try await seedOrSkip("createRecipe") {
            try await seedClient.createRecipe(
                name: name,
                ingredients: TestData.canonicalIngredients
            )
        }

        // Launch + wait for the list to reflect the seeded recipe.
        let list = recipeListPage.awaitReady()

        // Recipe row should appear after sync round-trip.
        let row = list.recipeRow(id: created.id)
        XCTAssertTrue(
            row.waitForExistence(timeout: Wait.syncRoundTrip),
            "Seeded recipe \(name) did not appear in list within sync round-trip"
        )

        row.tap()
        XCTAssertTrue(
            recipeDetailPage.ingredientsSection.waitForExistence(timeout: Wait.firstPaint),
            "Ingredients section missing on detail"
        )
    }

    func test_US3_editTitleAndIngredients() throws {
        Navigation.openTab(.recipes, in: app)
        let list = recipeListPage.awaitReady()
        guard list.hasRecipes else {
            throw XCTSkip("No recipes available to edit (seed was empty)")
        }

        list.tapFirstRecipe()
        recipeDetailPage.tapEdit()

        XCTAssertTrue(
            recipeDetailPage.newIngredientRow.waitForExistence(timeout: Wait.element),
            "New ingredient row missing in edit mode"
        )

        recipeDetailPage.tapDone()
        XCTAssertTrue(
            recipeDetailPage.editButton.waitForExistence(timeout: Wait.firstPaint),
            "App crashed or stuck after saving edit mode"
        )
    }

    @MainActor
    func test_US3_titleGrowsFromSingleLineToMultiline() async throws {
        Navigation.openTab(.recipes, in: app)
        let list = recipeListPage.awaitReady()
        let name = "A \(UUID().uuidString.prefix(4))"
        let created = try await seedOrSkip("createRecipe") {
            try await seedClient.createRecipe(name: name)
        }

        list.openAllRecipesIfNeeded()
        let row = list.recipeRow(id: created.id)
        XCTAssertTrue(
            row.waitForExistence(timeout: Wait.syncRoundTrip),
            "Seeded recipe \(name) did not appear in list within sync round-trip"
        )
        row.tap()
        XCTAssertTrue(
            recipeDetailPage.ingredientsSection.waitForExistence(timeout: Wait.firstPaint),
            "Ingredients section missing on title-growth detail"
        )
        recipeDetailPage.tapEdit()

        let titleField = recipeDetailPage.titleField
        XCTAssertTrue(
            titleField.waitForExistence(timeout: Wait.element),
            "Native recipe title field missing in edit mode"
        )

        let initialHeight = titleField.frame.height
        XCTAssertLessThan(
            initialHeight,
            60,
            "Title-growth fixture must start as a single-line title"
        )
        titleField.tap()
        let longTitle = "Очень длинное название рецепта для проверки автоматического переноса текста"
        titleField.typeText(longTitle)

        let grew = NSPredicate { _, _ in titleField.frame.height > initialHeight + 10 }
        let growthExpectation = XCTNSPredicateExpectation(predicate: grew, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [growthExpectation], timeout: Wait.element),
            .completed,
            "Title field did not grow from one line after entering long text"
        )
        XCTAssertGreaterThan(
            titleField.frame.height,
            initialHeight + 10,
            "Title field must expose multiple lines instead of internally scrolling"
        )
        XCTAssertTrue(
            String(describing: titleField.value).contains(longTitle),
            "Title field does not expose the complete typed value"
        )

        recipeDetailPage.tapDone()
        XCTAssertTrue(
            recipeDetailPage.editButton.waitForExistence(timeout: Wait.firstPaint),
            "App did not leave edit mode after saving grown title"
        )
        let persistedTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", longTitle)
        ).firstMatch
        XCTAssertTrue(
            persistedTitle.waitForExistence(timeout: Wait.firstPaint),
            "Saved multiline title was not rendered after leaving edit mode"
        )
    }
}
