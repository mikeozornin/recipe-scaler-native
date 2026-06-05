import XCTest

final class RecipeScalerNativeUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAuthScreenAppears() {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing"]
        app.launch()

        let newUserButton = app.buttons["auth_new_user_button"]
        XCTAssertTrue(newUserButton.waitForExistence(timeout: 5.0))
    }

    func testDescriptionTimerTapShowsStartPopover() {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing", "-SkipSplash=1", "-ShowDescriptionFixture"]
        app.launch()

        let fixture = app.otherElements["description-fixture-preview"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 10))

        let timerText = app.staticTexts["30 minutes"]
        XCTAssertTrue(
            timerText.waitForExistence(timeout: 5),
            "Timer reference should be visible in description"
        )
        timerText.tap()

        let popover = app.otherElements["description_timer_start_popover"]
        XCTAssertTrue(
            popover.waitForExistence(timeout: 5),
            "Tap on timer reference should present start popover"
        )

        let startButton = app.buttons["description_timer_start_confirm"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2))
        XCTAssertTrue(startButton.frame.height >= 40, "Start timer control should be at least ~44pt tap height")
    }

    func testOpenRecipeEnterEditAndDoneWithoutCrash() throws {
        let app = XCUIApplication()
        app.launch()

        let list = app.otherElements["recipe_list"]
        XCTAssertTrue(
            list.waitForExistence(timeout: 45),
            "Recipe list did not load — check network and debug user collection"
        )

        let firstRecipe = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "recipe_row_"))
            .firstMatch
        try XCTSkipIf(!firstRecipe.waitForExistence(timeout: 5), "No recipes in collection")

        firstRecipe.tap()

        let editButton = app.navigationBars.buttons["Edit"]
        try XCTSkipIf(!editButton.waitForExistence(timeout: 15), "Edit unavailable (legacy recipe or still loading)")

        editButton.tap()

        XCTAssertTrue(
            app.staticTexts["Ingredient"].waitForExistence(timeout: 10)
                || app.staticTexts["Ингредиент"].waitForExistence(timeout: 1),
            "Ingredient column header missing in edit mode"
        )

        let reorderControls = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", "Reorder", "Reorder")
        )
        XCTAssertGreaterThan(
            reorderControls.count,
            0,
            "List reorder controls should appear on ingredient rows in edit mode"
        )

        add(XCTAttachment(screenshot: XCUIScreen.main.screenshot(), name: "ingredients-edit-grid"))

        let doneButton = app.navigationBars.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        XCTAssertTrue(
            editButton.waitForExistence(timeout: 10),
            "App crashed or stuck after saving edit mode"
        )
    }

    /// Simulator E2E: manual add, recipe menu add-all, list swipe add-all (debug user + network).
    func testShoppingListAddFlowsOnSimulator() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SkipSplash=1"]
        app.launch()

        let shoppingTab = app.buttons["tab_shopping"]
        XCTAssertTrue(shoppingTab.waitForExistence(timeout: 45), "Shopping tab missing")

        let manualLabel = "UITest Milk \(UUID().uuidString.prefix(6))"
        try addManualShoppingItem(app: app, shoppingTab: shoppingTab, label: String(manualLabel))

        let recipesTab = app.buttons["tab_recipes"]
        XCTAssertTrue(recipesTab.waitForExistence(timeout: 5))
        recipesTab.tap()

        let list = app.otherElements["recipe_list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45), "Recipe list did not load")

        let firstRecipe = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "recipe_row_"))
            .firstMatch
        try XCTSkipIf(!firstRecipe.waitForExistence(timeout: 10), "No recipes in collection")

        try swipeAddWholeRecipeToShopping(app: app, firstRecipe: firstRecipe)

        firstRecipe.tap()
        let menu = app.buttons["recipe_detail_menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "Recipe detail menu missing")
        try addAllFromRecipeMenu(app: app, menu: menu)

        try addFirstIngredientViaSwipe(app: app)

        shoppingTab.tap()
        let shoppingRoot = app.otherElements["shopping_list"]
        XCTAssertTrue(shoppingRoot.waitForExistence(timeout: 10))

        let manualRow = app.staticTexts[manualLabel]
        XCTAssertTrue(
            manualRow.waitForExistence(timeout: 10),
            "Manual shopping item should appear in list"
        )

        add(XCTAttachment(screenshot: XCUIScreen.main.screenshot(), name: "shopping-list-after-adds"))
    }

    private func addManualShoppingItem(app: XCUIApplication, shoppingTab: XCUIElement, label: String) {
        shoppingTab.tap()
        XCTAssertTrue(app.otherElements["shopping_list"].waitForExistence(timeout: 10))

        let field = app.textFields["shopping_add_field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Shopping add field missing")
        field.tap()
        field.typeText(label + "\n")

        XCTAssertTrue(
            app.staticTexts[label].waitForExistence(timeout: 10),
            "Typed item should show in shopping list"
        )
    }

    private func swipeAddWholeRecipeToShopping(app: XCUIApplication, firstRecipe: XCUIElement) throws {
        firstRecipe.swipeRight()
        let addAllSwipe = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                "shopping list",
                "список покупок"
            )
        ).firstMatch
        if addAllSwipe.waitForExistence(timeout: 3) {
            addAllSwipe.tap()
            dismissShoppingAlertIfNeeded(app: app)
            return
        }
        let cartSwipe = app.buttons.matching(
            NSPredicate(format: "identifier CONTAINS[c] %@ OR label CONTAINS[c] %@", "cart", "корзин")
        ).firstMatch
        try XCTSkipIf(!cartSwipe.waitForExistence(timeout: 2), "Recipe list shopping swipe action not found")
        cartSwipe.tap()
        dismissShoppingAlertIfNeeded(app: app)
    }

    private func addAllFromRecipeMenu(app: XCUIApplication, menu: XCUIElement) throws {
        menu.tap()
        let addAll = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                "Add to shopping",
                "В список покупок"
            )
        ).firstMatch
        try XCTSkipIf(!addAll.waitForExistence(timeout: 5), "Add-all menu item missing (legacy recipe?)")
        addAll.tap()
        dismissShoppingAlertIfNeeded(app: app)
    }

    private func addFirstIngredientViaSwipe(app: XCUIApplication) throws {
        XCTAssertTrue(
            app.otherElements["ingredients_section"].waitForExistence(timeout: 15),
            "Ingredients section missing"
        )
        let ingredientCell = app.cells.element(boundBy: 1)
        try XCTSkipIf(!ingredientCell.waitForExistence(timeout: 5), "No ingredient row for swipe")
        ingredientCell.swipeRight()
        let addIngredient = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label == %@ OR label == %@",
                "Add to list",
                "В список",
                "Add to list",
                "В список"
            )
        ).firstMatch
        try XCTSkipIf(!addIngredient.waitForExistence(timeout: 3), "Ingredient shopping swipe missing")
        addIngredient.tap()
        dismissShoppingAlertIfNeeded(app: app)

        if app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 2) {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    private func dismissShoppingAlertIfNeeded(app: XCUIApplication) {
        let ok = app.alerts.buttons["OK"]
        if ok.waitForExistence(timeout: 2) {
            ok.tap()
        }
    }
}
