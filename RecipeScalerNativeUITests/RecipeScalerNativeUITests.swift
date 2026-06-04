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
}
