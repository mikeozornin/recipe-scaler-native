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
            app.staticTexts["Ingredients"].waitForExistence(timeout: 10),
            "Ingredients section missing in edit mode"
        )

        let dragHandles = app.images.matching(identifier: "line.3.horizontal")
        XCTAssertEqual(dragHandles.count, 0, "Custom drag handle should not appear alongside List reorder")

        let doneButton = app.navigationBars.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        XCTAssertTrue(
            editButton.waitForExistence(timeout: 10),
            "App crashed or stuck after saving edit mode"
        )
    }
}
