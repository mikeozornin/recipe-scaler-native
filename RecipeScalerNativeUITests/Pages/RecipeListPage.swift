import XCTest

/// Recipe list screen (`-OpenTab=recipes`).
///
/// Web parity: `recipeList` namespace in `helpers/selectors.ts`.
///
/// Default Recipes-tab UI is the **collections grid**, not a plain list.
/// `recipe_list` only exists when the flat recipe List is shown — do not
/// use it as the "tab ready" signal.
struct RecipeListPage: Page {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Root element of the plain recipe List (only when list mode is shown).
    /// Prefer `awaitReady` / `addButton` / `allCollectionsTile` for readiness.
    var list: XCUIElement {
        app.descendants(matching: .any)[UIA.recipeList].firstMatch
    }

    /// "+" button to create a new recipe (always present on Recipes tab).
    var addButton: XCUIElement { app.buttons[UIA.recipeListAdd] }

    /// Virtual "All recipes" grid tile (always present on collections grid).
    var allCollectionsTile: XCUIElement {
        app.descendants(matching: .any)[UIA.collectionsRootGridTile(folderId: "all")].firstMatch
    }

    /// First recipe row (any id). Use for "tap any recipe" scenarios.
    var firstRecipeRow: XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", UIA.recipeRowPrefix)
        ).firstMatch
    }

    /// Specific recipe row by id (after REST seeding).
    func recipeRow(id: String) -> XCUIElement {
        // Wide iPad selection uses an onTapGesture-backed accessibility
        // element rather than a Button; compact navigation uses a Button.
        // Query the stable identifier across both roles.
        app.descendants(matching: .any)[UIA.recipeRow(id: id)].firstMatch
    }

    /// True if at least one recipe row is showing.
    var hasRecipes: Bool {
        firstRecipeRow.waitForExistence(timeout: Wait.element)
    }

    /// Wait for the Recipes tab to be ready.
    ///
    /// Ready = `recipe_list_add` button **or** `collection_grid_all` tile.
    /// Do not wait on `recipe_list` — that id is absent on the default
    /// collections-grid UI.
    ///
    /// Uses `XCTNSPredicateExpectation` + `XCTWaiter` (instead of a manual
    /// `RunLoop` busy-poll) so the wait cooperates with the system's main-
    /// thread runloop. See review finding Performance Critical #5.
    @discardableResult
    func awaitReady(timeout: TimeInterval = Wait.firstPaint) -> Self {
        let add = addButton
        let allTile = allCollectionsTile
        let ready = NSPredicate { _, _ in add.exists || allTile.exists }
        let expectation = XCTNSPredicateExpectation(predicate: ready, object: nil)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        if result == .completed {
            return self
        }
        if add.exists || allTile.exists {
            return self
        }
        XCTFail(
            "Recipes tab not ready within \(Int(timeout))s — need recipe_list_add or collection_grid_all"
        )
        return self
    }

    /// Tap the first recipe row; returns the detail page.
    @discardableResult
    func tapFirstRecipe() -> RecipeDetailPage {
        guard firstRecipeRow.waitForExistence(timeout: Wait.element) else {
            XCTFail("No recipe row to tap")
            return RecipeDetailPage(app: app)
        }
        firstRecipeRow.tap()
        return RecipeDetailPage(app: app)
    }

    /// Tap the "+" button to start the new-recipe flow.
    @discardableResult
    func tapAddRecipe() -> Self {
        guard addButton.waitForExistence(timeout: Wait.element) else {
            XCTFail("Recipe list add button missing")
            return self
        }
        addButton.tap()
        return self
    }

    /// Open the virtual "All recipes" folder when the collections grid is showing.
    /// No-op if recipe rows are already visible (list mode / already drilled in).
    @discardableResult
    func openAllRecipesIfNeeded() -> Self {
        if firstRecipeRow.exists { return self }
        let tile = allCollectionsTile
        if tile.waitForExistence(timeout: Wait.element) {
            tile.tap()
        }
        return self
    }
}
