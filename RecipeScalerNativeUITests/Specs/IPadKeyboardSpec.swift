import UIKit
import XCTest

/// Spec coverage: specs/081-ipad-adaptation/spec.md, US6 (keyboard and menu bar), T048.
///
/// iPad only, iPadOS 26.2+, landscape with the sidebar hidden, so the recipe opens in two
/// columns beside the list. The shortcuts of layout.md §Меню are pressed with
/// `typeKey(_:modifierFlags:)`: XCTest sends hardware key events, so the spec runs with
/// `ConnectHardwareKeyboard` at 0 or 1 and without the Simulator window. Its limits:
/// - the first key event after the launch can be lost, so each test presses an unbound
///   ⌘K first (`warmUpKeyboard`);
/// - ⌘↩ and ⌘⌫ (any Return shortcut, `.delete` or "\u{8}") from `typeKey` never reach the
///   app on the iPadOS 26.3 simulator, while the same keys sent as HID events do.
///   `testHostKeys` asks `scripts/verify-ipad-keyboard.sh` for them (`axe key-combo`) and
///   is skipped without it; the other tests tap «Готово»;
/// - `typeKey("+", .command)` adds ⇧, so ⌘+ is pressed as ⌘=, which the item matches;
/// - the menu bar itself is not in the accessibility tree: an inactive item is checked
///   by its shortcut doing nothing.
///
/// Every test gets a fresh user with one recipe seeded over REST and the DEBUG assistant
/// fixture (`-ScreenshotAssistantFixture=1`) for ⌘J. A recipe created over REST cannot be
/// edited (old format) or take ingredients over REST, so the edit shortcuts and ⇧⌘L use a
/// recipe made with ⌘N.
final class IPadKeyboardSpec: BaseTestCase {
    private var recipe: SeedClient.CreatedRecipe!
    private static let ingredient = "Kbd flour 081"

    @MainActor
    override func setUp() async throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "iPad keyboard shortcuts (spec 081) — iPad only"
        )
        try XCTSkipUnless(
            ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 26, minorVersion: 2, patchVersion: 0)
            ),
            "The spec checks the iPadOS 26.2+ shell (top bar tabs, ⇧⌘N alert, ⌃⌘S, assistant panel)"
        )
        try await super.setUp()
        rotate(to: .landscapeLeft)
    }

    @MainActor
    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
        try await super.tearDown()
    }

    override func extraLaunchArguments() -> [String] {
        ["-OpenTab=recipes", "-IPadSidebarHidden=1", "-ScreenshotAssistantFixture=1"]
    }

    override func prepareBeforeLaunch() async throws {
        recipe = try await seedOrSkip("POST /api/recipes") {
            try await self.seedClient.createRecipe(name: TestData.recipeName("E2E Keys"))
        }
    }

    // MARK: - «Рецепт»

    /// Scenario 2 and the rest of «Рецепт» on the open recipe: servings, «Не гасить экран»,
    /// «Закрепить» («В список покупок»: `testEditShortcuts`; «Удалить», ⌘⌫: `testHostKeys`).
    func testRecipeShortcuts() {
        awaitRecipe()
        warmUpKeyboard()

        // ⌘+ / ⌘− / ⌘0: the servings stepper.
        guard let start = servings else {
            XCTFail("No servings value on the recipe")
            return
        }
        press("=")
        XCTAssertTrue(waitUntil { self.servings == start + 1 }, "⌘+ did not add a serving: \(servingsText)")
        press("=")
        XCTAssertTrue(waitUntil { self.servings == start + 2 }, "The second ⌘+ did not add a serving: \(servingsText)")
        press("-")
        XCTAssertTrue(waitUntil { self.servings == start + 1 }, "⌘− did not remove a serving: \(servingsText)")
        press("0")
        XCTAssertTrue(waitUntil { self.servings == start }, "⌘0 did not restore \(start) servings: \(servingsText)")

        // ⌃⌘A: «Не гасить экран» flips the toolbar toggle.
        let awake = app.buttons.matching(identifier: UIA.screenAwakeToggle).firstMatch
        XCTAssertTrue(awake.waitForExistence(timeout: Wait.element), "No «Не гасить экран» in the toolbar")
        let awakeOff = awake.label
        press("a", [.command, .control])
        XCTAssertTrue(waitUntil { awake.label != awakeOff }, "⌃⌘A did not turn «Не гасить экран» on: «\(awake.label)»")
        press("a", [.command, .control])
        XCTAssertTrue(waitUntil { awake.label == awakeOff }, "The second ⌃⌘A did not turn it off: «\(awake.label)»")

        // ⇧⌘P: «…» offers «Открепить» after it.
        press("p", [.command, .shift])
        recipeDetailPage.menuButton.tap()
        XCTAssertTrue(menuItem(Self.unpin).waitForExistence(timeout: Wait.syncRoundTrip), "⇧⌘P did not pin the recipe")
        XCTAssertFalse(menuItem(Self.pin).exists, "A pinned recipe still offers «Закрепить»")
        dismissMenu()
    }

    /// Scenario 1: ⌘N opens a new recipe in the edit, ⌘E opens the edit again, and during
    /// the edit only «Готово» is active. ⇧⌘L sends the ingredient added in the edit to
    /// «Покупки». «Готово» is tapped here; ⌘↩ is in `testHostKeys`.
    func testEditShortcuts() {
        awaitRecipe()
        warmUpKeyboard()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", UIA.recipeRowPrefix))
        XCTAssertTrue(waitUntil { rows.count == 1 }, "Expected one seeded row, got \(rows.count)")

        // ⌘N: «Новый рецепт» of the list «+».
        press("n")
        let done = app.buttons.matching(identifier: UIA.recipeDetailDone).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: Wait.syncRoundTrip), "⌘N did not open a new recipe in the edit")
        XCTAssertTrue(recipeDetailPage.titleField.waitForExistence(timeout: Wait.element), "The new recipe has no title field")
        addIngredient(Self.ingredient, amount: "200")

        // In the edit the other commands are off, as the toolbar has only «Готово».
        press("n")
        XCTAssertTrue(done.exists, "⌘N left the edit")
        press("p", [.command, .shift])
        done.tap()
        XCTAssertTrue(waitUntil { !done.exists }, "«Готово» did not finish the edit")
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", Self.ingredient)).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: Wait.element), "«\(Self.ingredient)» is not in the recipe after «Готово»")
        // The edit expanded the recipe over the list and «Готово» keeps it so (T041):
        // «Свернуть» brings the list back.
        let collapse = app.buttons.matching(identifier: UIA.ipadRecipeExpandButton).firstMatch
        XCTAssertTrue(collapse.waitForExistence(timeout: Wait.element), "No «Свернуть» after the edit")
        collapse.tap()
        XCTAssertTrue(waitUntil(timeout: Wait.syncRoundTrip) { rows.count == 2 }, "⌘N added no row: \(rows.count)")

        // ⌘E: «Изменить» of the recipe on screen.
        let edit = app.buttons.matching(identifier: UIA.recipeDetailEdit).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: Wait.element), "No «Изменить» after «Готово»")
        recipeDetailPage.menuButton.tap()
        XCTAssertTrue(menuItem(Self.pin).waitForExistence(timeout: Wait.element), "⇧⌘P pinned the recipe during the edit")
        dismissMenu()
        press("e")
        XCTAssertTrue(done.waitForExistence(timeout: Wait.element), "⌘E did not open the edit")
        done.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: Wait.element), "«Готово» did not finish the second edit")

        // ⇧⌘L: the ingredient lands in «Покупки» (⌘3 opens it).
        press("l", [.command, .shift])
        press("3")
        shoppingListPage.awaitReady()
        let item = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", Self.ingredient)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: Wait.syncRoundTrip), "⇧⌘L did not add «\(Self.ingredient)» to «Покупки»")
    }

    /// Scenario 5: with no recipe on screen the «Рецепт» commands do nothing (⌘⌫:
    /// `testHostKeys`).
    func testRecipeMenuInactiveWithoutRecipe() {
        awaitRecipe()
        warmUpKeyboard()
        guard let start = servings else {
            XCTFail("No servings value on the recipe")
            return
        }
        let awake = app.buttons.matching(identifier: UIA.screenAwakeToggle).firstMatch
        XCTAssertTrue(awake.waitForExistence(timeout: Wait.element), "No «Не гасить экран» in the toolbar")
        let awakeLabel = awake.label

        press("3")
        shoppingListPage.awaitReady()
        press("=")
        press("p", [.command, .shift])
        press("a", [.command, .control])

        press("2")
        awaitTwoColumns()
        XCTAssertEqual(servings, start, "⌘+ changed the servings off screen")
        XCTAssertEqual(awake.label, awakeLabel, "⌃⌘A changed «Не гасить экран» off screen")
        recipeDetailPage.menuButton.tap()
        XCTAssertTrue(menuItem(Self.pin).waitForExistence(timeout: Wait.element), "⇧⌘P pinned the recipe off screen")
        dismissMenu()
    }

    // MARK: - «Вид»

    /// Scenario 3: ⌃⌘S, ⌘1–⌘4 (⌘4 is the «Моё всё» sheet in a wide window), ⌘J, ⌘F.
    func testViewShortcuts() {
        awaitRecipe()
        warmUpKeyboard()

        // ⌃⌘S (the system «Show Sidebar»): the sidebar's own toggle shows while it is open.
        let sidebarToggle = app.buttons.matching(identifier: "ToggleSidebar").firstMatch
        press("s", [.command, .control])
        XCTAssertTrue(waitUntil { sidebarToggle.exists && sidebarToggle.isHittable }, "⌃⌘S did not show the sidebar")
        press("s", [.command, .control])
        XCTAssertTrue(waitUntil { !(sidebarToggle.exists && sidebarToggle.isHittable) }, "The second ⌃⌘S did not hide the sidebar")

        press("1")
        XCTAssertTrue(waitUntil { self.topBarTab(UIA.tabDiscover).isSelected }, "⌘1 did not open «Подборки»")
        press("3")
        shoppingListPage.awaitReady()
        XCTAssertTrue(waitUntil { self.topBarTab(UIA.tabShopping).isSelected }, "⌘3 did not open «Покупки»")

        press("4")
        XCTAssertTrue(profileDoneButton.waitForExistence(timeout: Wait.element), "⌘4 did not open the «Моё всё» sheet")
        accountPage.awaitReady()
        XCTAssertTrue(topBarTab(UIA.tabShopping).isSelected, "⌘4 moved the selection off «Покупки»")

        press("2")
        XCTAssertTrue(waitUntil { !self.accountPage.root.exists }, "⌘2 left the «Моё всё» sheet open")
        XCTAssertTrue(waitUntil { self.topBarTab(UIA.tabRecipes).isSelected }, "⌘2 did not open «Рецепты»")
        awaitTwoColumns()

        // ⌘J opens and closes the assistant panel.
        press("j")
        let close = app.buttons.matching(identifier: UIA.ipadAssistantInspectorCloseButton).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: Wait.element), "⌘J did not open the assistant")
        press("j")
        XCTAssertTrue(waitUntil { !close.exists }, "The second ⌘J did not close the assistant")

        // ⌘F: the search field of the list takes the focus and the typing.
        press("f")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Wait.element), "No recipe search field after ⌘F")
        XCTAssertTrue(waitUntil { self.hasFocus(search) }, "⌘F did not focus the recipe search")
        app.typeText("Keys")
        XCTAssertTrue(
            waitUntil { ((search.value as? String) ?? "").contains("Keys") },
            "Typing after ⌘F did not reach the search field: «\(search.value as? String ?? "")»"
        )
    }

    // MARK: - «Файл»

    /// Scenario 4: ⇧⌘N and ⇧⌘I by the phone paths (⌘N: `testEditShortcuts`).
    func testFileShortcuts() {
        awaitRecipe()
        warmUpKeyboard()

        // ⇧⌘N: the «Новая коллекция» alert.
        press("n", [.command, .shift])
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: Wait.element), "⇧⌘N did not open «Новая коллекция»")
        XCTAssertTrue(alert.textFields.firstMatch.exists, "The «Новая коллекция» alert has no name field")
        alert.buttons.matching(NSPredicate(format: "label IN %@", Self.cancel)).firstMatch.tap()
        XCTAssertTrue(waitUntil { !alert.exists }, "«Отмена» did not close «Новая коллекция»")

        // ⇧⌘I: the import sheet.
        press("i", [.command, .shift])
        XCTAssertTrue(importPage.sheet.waitForExistence(timeout: Wait.element), "⇧⌘I did not open the import")
    }

    // MARK: - Host keys

    /// ⌘⌫ (scenarios 2 and 5) and ⌘↩ (scenario 1), which `typeKey` cannot press. For each
    /// key the test prints `IPAD_KEYBOARD_HOST_KEY <n> <combo>`, `verify-ipad-keyboard.sh`
    /// sends the combo as HID events, and the test waits for what it did, then prints
    /// `IPAD_KEYBOARD_HOST_KEY_SEEN <n>`. A key that must do nothing is followed by ⌘2,
    /// whose effect shows that both keys arrived.
    func testHostKeys() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["IPAD_KEYBOARD_HOST_KEYS"] == "1",
            "⌘⌫ and ⌘↩ need HID keys from the host: bash scripts/verify-ipad-keyboard.sh"
        )
        awaitRecipe()
        warmUpKeyboard()
        let done = app.buttons.matching(identifier: UIA.recipeDetailDone).firstMatch

        // ⌘⌫ on the open recipe: the phone's confirmation; the test cancels it.
        requestHostKey(1, "cmd-delete")
        let confirm = deleteConfirmation
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.hostKeyTimeout), "⌘⌫ showed no delete confirmation")
        hostKeySeen(1)
        let cancel = app.alerts.firstMatch.buttons.matching(NSPredicate(format: "label IN %@", Self.cancel)).firstMatch
        XCTAssertTrue(cancel.exists, "The confirmation has no «Отмена»")
        cancel.tap()
        XCTAssertTrue(waitUntil { !confirm.exists }, "«Отмена» did not close the confirmation")
        XCTAssertTrue(recipeListPage.recipeRow(id: recipe.id).exists, "The recipe is gone after «Отмена»")

        // ⌘⌫ in «Покупки», with no recipe on screen, asks nothing.
        press("3")
        shoppingListPage.awaitReady()
        requestHostKey(2, "cmd-delete")
        requestHostKey(3, "cmd-2")
        XCTAssertTrue(
            waitUntil(timeout: Self.hostKeyTimeout) { self.topBarTab(UIA.tabRecipes).isSelected },
            "The host ⌘2 did not open «Рецепты»"
        )
        awaitTwoColumns()
        XCTAssertFalse(confirm.exists, "⌘⌫ asked to delete a recipe that was not on screen")
        hostKeySeen(2)
        hostKeySeen(3)

        // ⌘↩ with the focus in the title field of a new recipe (⌘N) finishes the edit.
        press("n")
        XCTAssertTrue(done.waitForExistence(timeout: Wait.syncRoundTrip), "⌘N did not open a new recipe in the edit")
        let title = recipeDetailPage.titleField
        XCTAssertTrue(title.waitForExistence(timeout: Wait.element), "The new recipe has no title field")
        title.tap()
        app.typeText(Self.hostTitle)
        requestHostKey(4, "cmd-return")
        XCTAssertTrue(
            waitUntil(timeout: Self.hostKeyTimeout) { !done.exists },
            "⌘↩ in the title field did not finish the edit"
        )
        hostKeySeen(4)
        XCTAssertTrue(
            labelled(Self.hostTitle).waitForExistence(timeout: Wait.syncRoundTrip),
            "The title typed before ⌘↩ was not kept"
        )

        // ⌘↩ with the focus in the steps editor (a web view) finishes the edit too.
        press("e")
        XCTAssertTrue(done.waitForExistence(timeout: Wait.element), "⌘E did not open the edit")
        focusStepsEditor()
        app.typeText(Self.hostStep)
        requestHostKey(5, "cmd-return")
        XCTAssertTrue(
            waitUntil(timeout: Self.hostKeyTimeout) { !done.exists },
            "⌘↩ in the steps editor did not finish the edit"
        )
        hostKeySeen(5)
        XCTAssertTrue(
            labelled(Self.hostStep).waitForExistence(timeout: Wait.element),
            "The step typed before ⌘↩ was not kept"
        )

        // In the search field ⌘⌫ edits the text and asks nothing, with a recipe on screen.
        press("f")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(waitUntil { self.hasFocus(search) }, "⌘F did not focus the recipe search")
        app.typeText("Keys")
        XCTAssertTrue(waitUntil { self.searchText(search).contains("Keys") }, "Typing did not reach the search field")
        requestHostKey(6, "cmd-delete")
        XCTAssertTrue(
            waitUntil(timeout: Self.hostKeyTimeout) { !self.searchText(search).contains("Keys") },
            "⌘⌫ did not delete the search text: «\(searchText(search))»"
        )
        XCTAssertFalse(confirm.exists, "⌘⌫ in the search field asked to delete the recipe")
        hostKeySeen(6)
    }

    // MARK: - Helpers

    private static let pin = ["Закрепить", "Pin"]
    private static let unpin = ["Открепить", "Unpin"]
    private static let cancel = ["Отмена", "Cancel"]

    private static let hostTitle = "Host keys 081"
    private static let hostStep = "Host step 081"
    /// The script waits 2 s after a marker before it sends the key.
    private static let hostKeyTimeout: TimeInterval = 60

    /// Asks `scripts/verify-ipad-keyboard.sh` for a key combo (`testHostKeys`).
    private func requestHostKey(_ step: Int, _ combo: String) {
        print("IPAD_KEYBOARD_HOST_KEY \(step) \(combo)")
        fflush(stdout)
    }

    private func hostKeySeen(_ step: Int) {
        print("IPAD_KEYBOARD_HOST_KEY_SEEN \(step)")
        fflush(stdout)
    }

    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func searchText(_ field: XCUIElement) -> String {
        field.exists ? ((field.value as? String) ?? "") : ""
    }

    /// The steps editor is a web view; it has the focus once its formatting bar shows.
    private func focusStepsEditor() {
        let editor = app.webViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: Wait.firstPaint), "No steps editor in the edit")
        let bar = app.descendants(matching: .any).matching(identifier: "description_formatting_bar").firstMatch
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if !bar.waitForExistence(timeout: 3) {
            editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(bar.waitForExistence(timeout: Wait.element), "The steps editor did not take the focus")
    }

    /// The first key event after the launch can be lost: an unbound ⌘K takes that place.
    private func warmUpKeyboard() {
        press("k")
        Thread.sleep(forTimeInterval: 0.5)
    }

    private var deleteConfirmation: XCUIElement {
        app.buttons.matching(identifier: UIA.recipeDetailDeleteConfirm).firstMatch
    }

    private func press(_ key: String, _ flags: XCUIElement.KeyModifierFlags = .command) {
        app.typeKey(key, modifierFlags: flags)
    }

    private var servingsText: String {
        app.staticTexts.matching(identifier: UIA.recipeDetailServingsValue).firstMatch.label
    }

    private var servings: Int? {
        let text = servingsText
        guard !text.isEmpty else { return nil }
        return Int(text.filter(\.isNumber))
    }

    private func topBarTab(_ id: String) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    private func menuItem(_ labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private var profileDoneButton: XCUIElement {
        app.buttons
            .matching(NSPredicate(
                format: "identifier == %@ OR label IN %@",
                UIA.ipadProfileSheetDoneButton,
                ["Готово", "Done"]
            ))
            .firstMatch
    }

    private func hasFocus(_ element: XCUIElement) -> Bool {
        element.exists && ((element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false)
    }

    /// Types an ingredient with an amount into the new-ingredient row of the edit and
    /// submits it (without an amount the row is a section header, which «В список покупок»
    /// skips). In landscape the software keyboard of the title (`ConnectHardwareKeyboard` 0)
    /// covers the row, so the row is filled in portrait, where it stays above the keyboard.
    /// The title of a new recipe takes the focus back from a tap elsewhere
    /// (`RecipeTitleTextField`: an incidental blur keeps the title editing), so its keyboard
    /// «Готово» lets it go first.
    private func addIngredient(_ name: String, amount: String) {
        rotate(to: .portrait)
        defer { rotate(to: .landscapeLeft) }
        let title = recipeDetailPage.titleField
        let titleDone = app.buttons[UIA.recipeTitleKeyboardDone]
        if titleDone.waitForExistence(timeout: 3) {
            titleDone.tap()
        }
        XCTAssertTrue(waitUntil { !self.hasFocus(title) }, "The title kept the focus after its «Готово»")
        // The row's identifier covers its children: the name and amount text fields and
        // the submit button («Return») carry it instead of their own.
        let row = UIA.recipeEditNewIngredientRow
        let fields = app.textFields.matching(identifier: row)
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: Wait.element), "No new-ingredient row in the edit")
        let byX = fields.allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
        guard byX.count == 2, let nameField = byX.first, let amountField = byX.last else {
            return XCTFail("Expected the name and amount fields in the new-ingredient row, got \(byX.count)")
        }
        nameField.tap()
        XCTAssertTrue(waitUntil { self.hasFocus(nameField) }, "The new-ingredient name field did not take the focus")
        app.typeText(name)
        amountField.tap()
        XCTAssertTrue(waitUntil { self.hasFocus(amountField) }, "The new-ingredient amount field did not take the focus")
        app.typeText(amount)
        let submit = app.buttons.matching(identifier: row).firstMatch
        XCTAssertTrue(waitUntil { submit.exists && submit.isEnabled }, "The new ingredient cannot be submitted")
        // The amount's number pad is a popover over the row: a tap outside it only closes it.
        if !submit.isHittable {
            submit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = waitUntil { !submit.isEnabled || submit.isHittable }
        }
        if submit.isEnabled {
            submit.tap()
        }
        // The row empties and the ingredient becomes a row of the list.
        XCTAssertTrue(waitUntil { self.text(of: nameField) != name }, "The new-ingredient row kept «\(name)»")
        let added = app.descendants(matching: .any).matching(NSPredicate(
            format: "(label CONTAINS[c] %@ OR value CONTAINS[c] %@) AND identifier != %@", name, name, row
        )).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: Wait.element), "«\(name)» did not appear in the ingredients")
    }

    private func text(of field: XCUIElement) -> String {
        field.exists ? ((field.value as? String) ?? "") : ""
    }

    /// Closes an open «…» menu.
    private func dismissMenu() {
        app.typeKey(.escape, modifierFlags: [])
        if menuItem(Self.pin).exists || menuItem(Self.unpin).exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.9)).tap()
        }
        _ = waitUntil { !self.menuItem(Self.pin).exists && !self.menuItem(Self.unpin).exists }
    }

    private func awaitRecipe(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            recipeListPage.recipeRow(id: recipe.id).waitForExistence(timeout: Wait.syncRoundTrip),
            "Row «\(recipe.name)» missing",
            file: file,
            line: line
        )
        awaitTwoColumns(file: file, line: line)
    }

    private func awaitTwoColumns(file: StaticString = #filePath, line: UInt = #line) {
        let left = app.scrollViews.matching(identifier: UIA.ipadRecipeDetailLeftColumn).firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: Wait.firstPaint), "No left recipe column", file: file, line: line)
    }

    private func rotate(to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let wantsLandscape = orientation.isLandscape
        XCTAssertTrue(
            waitUntil {
                let frame = self.app.windows.firstMatch.frame
                return wantsLandscape == (frame.width > frame.height)
            },
            "The app did not turn to \(wantsLandscape ? "landscape" : "portrait")"
        )
        if wantsLandscape { hideSidebarIfShown() }
    }

    /// The system brings the landscape sidebar back after a rotation even when the app
    /// launched with it hidden. Its own toggle (`ToggleSidebar`) is the sign it is shown.
    private func hideSidebarIfShown() {
        let toggle = app.buttons.matching(identifier: "ToggleSidebar").firstMatch
        guard toggle.waitForExistence(timeout: 3), toggle.isHittable else { return }
        toggle.tap()
        XCTAssertTrue(waitUntil { !(toggle.exists && toggle.isHittable) }, "Sidebar did not hide")
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval = Wait.element, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
