import XCTest

/// Spec coverage: specs/008-collection-mutations/spec.md
///
/// Web parity: tests/e2e/specs/008-collection-mutations.spec.ts
///
///   - US1 — Create folder via UI ("+" tile on Recipes tab)
///
/// NOTE: US2 (rename), US3 (delete), US4 (assign) require multi-step UI flows
/// that depend on long-press / swipe gestures that are flaky in XCUITest.
/// They are covered indirectly by manual QA + unit tests on the yjs
/// mutation helpers (`shared/utils/folders-yjs.ts`).
final class CollectionMutationsSpec: BaseTestCase {
    @MainActor
    func test_US1_createFolderViaUI() {
        Navigation.openTab(.recipes, in: app)
        _ = recipeListPage.awaitReady()

        let newFolderTile = app.buttons[UIA.collectionsNewRow]
        XCTAssertTrue(newFolderTile.waitForExistence(timeout: Wait.element), "New-collection tile missing")
        newFolderTile.tap()

        // After tapping, a prompt appears for the name. Type a name and confirm.
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: Wait.element) {
            let textField = alert.textFields.firstMatch
            if textField.exists {
                textField.tap()
                textField.typeText("E2E Folder")
            }
            alert.buttons.firstMatch.tap()
        }

        // Verify a new collection tile appears (any id; we cannot predict it).
        let anyTile = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", UIA.collectionsRootGridTilePrefix)
        ).firstMatch
        XCTAssertTrue(
            anyTile.waitForExistence(timeout: Wait.syncRoundTrip),
            "New folder tile did not appear after create"
        )
    }
}
