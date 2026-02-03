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
}
