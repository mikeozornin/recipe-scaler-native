import UIKit
import XCTest

/// Spec coverage: specs/081-ipad-adaptation/spec.md, US6, T047 — the iPhone with a hardware
/// keyboard gets none of the iPad shortcuts.
///
/// iPhone only. The shortcuts are pressed on an open recipe with `typeKey`, then ⌘A in the
/// recipe search shows that ⌘ keys reach the app: it selects the typed text, which the
/// next letter replaces.
final class PhoneKeyboardSpec: BaseTestCase {
    private var recipe: SeedClient.CreatedRecipe!

    @MainActor
    override func setUp() async throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "The iPhone without the iPad shortcuts (spec 081 US6) — iPhone only"
        )
        try await super.setUp()
    }

    override func extraLaunchArguments() -> [String] {
        ["-OpenTab=recipes"]
    }

    override func prepareBeforeLaunch() async throws {
        recipe = try await seedOrSkip("POST /api/recipes") {
            try await self.seedClient.createRecipe(name: TestData.recipeName("E2E Phone keys"))
        }
    }

    func testIPadShortcutsDoNothingOnThePhone() {
        recipeListPage.awaitReady().openAllRecipesIfNeeded()
        let row = recipeListPage.recipeRow(id: recipe.id)
        XCTAssertTrue(row.waitForExistence(timeout: Wait.syncRoundTrip), "Row «\(recipe.name)» missing")
        row.tap()
        let servings = app.staticTexts.matching(identifier: UIA.recipeDetailServingsValue).firstMatch
        XCTAssertTrue(servings.waitForExistence(timeout: Wait.firstPaint), "No servings on the recipe")
        let start = servings.label

        // The first key after the launch can be lost; ⌘K is bound nowhere.
        press("k")
        Thread.sleep(forTimeInterval: 0.5)
        // ⌘+ (typed as ⌘=), ⌘E, ⇧⌘P, ⌘3, ⌘J, ⌘N: the iPad's servings, edit, pin, «Покупки»,
        // assistant and new recipe.
        press("=")
        press("e")
        press("p", [.command, .shift])
        press("3")
        press("j")
        press("n")
        Thread.sleep(forTimeInterval: 2)

        XCTAssertTrue(servings.exists, "A shortcut left the recipe")
        XCTAssertEqual(servings.label, start, "⌘+ changed the servings on the iPhone")
        XCTAssertFalse(recipeDetailPage.titleField.exists, "⌘E or ⌘N opened an edit on the iPhone")

        // The keys do reach the app: ⌘A selects the search text.
        Navigation.goBack(in: app)
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) {
            app.swipeDown()
        }
        XCTAssertTrue(search.waitForExistence(timeout: Wait.element), "No recipe search field")
        search.tap()
        search.typeText("kbd")
        XCTAssertTrue(waitUntil { self.text(of: search) == "kbd" }, "Typing did not reach the search field")
        press("a")
        app.typeText("z")
        XCTAssertTrue(
            waitUntil { self.text(of: search) == "z" },
            "⌘A did not reach the app, so the shortcut checks above prove nothing: «\(text(of: search))»"
        )
    }

    private func press(_ key: String, _ flags: XCUIElement.KeyModifierFlags = .command) {
        app.typeKey(key, modifierFlags: flags)
    }

    private func text(of field: XCUIElement) -> String {
        field.exists ? ((field.value as? String) ?? "") : ""
    }

    private func waitUntil(timeout: TimeInterval = Wait.element, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
