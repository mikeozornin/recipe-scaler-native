import UIKit
import XCTest

/// Spec coverage: specs/081-ipad-adaptation/spec.md, US2 (the Recipes split), T030.
///
/// iPad only, iPadOS 26.2+, landscape (1194–1210) with the sidebar hidden (`#recipes/tabs`):
/// the list column (a third of the content) beside the recipe panel, the recipe in two
/// columns. In portrait the list and the recipe split the width in half and the recipe
/// keeps one column. «Развернуть» gives the recipe the whole section (and hides a sidebar
/// beside it), «Свернуть» brings the list back, as in Apple Notes.
///
/// Every test gets a fresh user with two recipes seeded over REST (read-only «старый
/// формат» on iOS). Collections and membership live in the Yjs document and the local
/// backend has no `POST /api/collections`, so the collection test makes one in the
/// «В коллекцию» sheet; the toolbar check makes an editable recipe with «+».
///
/// Expanded, the list column's empty `NavigationStack` stays in the hierarchy off the
/// leading edge (an iPadOS bar workaround, see `IPadRecipesSplitView.split`), but its rows,
/// «+» and search field are gone: nothing for VoiceOver or Full Keyboard Access to reach.
///
/// No room for the list beside the recipe (push) needs a ⅔ landscape window with the
/// sidebar shown; the simulator cannot make one (`-DebugWindowWidth` under 680 pt is the
/// compact phone shell and keeps the sidebar hidden), so the push rule is covered by
/// `IPadLayoutPolicyTests` only.
///
/// `TEST_RUNNER_E2E_SCREENSHOTS=1` keeps screenshots of the checked states in the
/// result bundle (test users only, no real data). In landscape the XCTest screenshot on
/// the iPadOS 26 simulator is a cropped portrait buffer; take review shots with
/// `simctl io screenshot` instead.
final class IPadRecipesSpec: BaseTestCase {
    private var first: SeedClient.CreatedRecipe!
    private var second: SeedClient.CreatedRecipe!

    @MainActor
    override func setUp() async throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "iPad recipes split (spec 081) — iPad only"
        )
        try XCTSkipUnless(
            ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 26, minorVersion: 2, patchVersion: 0)
            ),
            "The split lives in the iPadOS 26.2+ shell; older systems keep the phone shell"
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
        ["-OpenTab=recipes", "-IPadSidebarHidden=1"]
    }

    override func prepareBeforeLaunch() async throws {
        let seeded = try await seedOrSkip("POST /api/recipes") {
            (
                try await self.seedClient.createRecipe(name: TestData.recipeName("E2E Alpha")),
                try await self.seedClient.createRecipe(name: TestData.recipeName("E2E Beta"))
            )
        }
        first = seeded.0
        second = seeded.1
    }

    // MARK: - Layout

    /// `#recipes/tabs`: the list column, the open recipe in two columns, the wide toolbar.
    func testListAndTwoColumns() {
        awaitRows()
        XCTAssertTrue(listOnScreen, "No list column in landscape")
        XCTAssertTrue(waitUntil { self.selectedRowCount == 1 }, "No recipe row is highlighted")
        awaitTwoColumns()

        let left = leftColumn.frame.width
        let right = rightColumn.frame.width
        XCTAssertTrue((399...401).contains(left), "Left recipe column is \(left) pt, expected 400")
        XCTAssertGreaterThanOrEqual(right, 320, "Steps column is \(right) pt, expected ≥ 320")
        // Landscape: the list takes a third of the content and its 1 pt divider follows it.
        assertListWidth(third: true)
        XCTAssertTrue(expandButton(reading: Self.expand).waitForExistence(timeout: Wait.element), "No «Развернуть» beside the list")
        XCTAssertFalse(element(UIA.ipadAssistantToolbarButton).exists, "A toolbar ✦ next to the «Ассистент» tab")
        capture("recipes-landscape")

        // The seeded recipes are read-only: «+» makes one with «Изменить» in the toolbar.
        recipeListPage.tapAddRecipe()
        let done = app.buttons.matching(identifier: UIA.recipeDetailDone).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: Wait.syncRoundTrip), "«+» did not open a new recipe for editing")
        done.tap()
        awaitTwoColumns()
        assertToolbarFits("own row")
        capture("recipes-tabs-landscape")

        // Back from the background the recipe toolbar keeps its items on the bar.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: Wait.element), "The app did not come back")
        awaitTwoColumns()
        assertToolbarFits("after the background")
        capture("recipes-tabs-landscape-after-foreground")
    }

    /// `#recipes/focus`: «Развернуть» gives the recipe the whole section, the state outlives
    /// a tab switch, «Свернуть» brings the list back. With the sidebar beside the content the
    /// recipe hides it too and «Свернуть» shows it again (Apple Notes).
    func testExpandCollapse() {
        awaitRows()
        awaitTwoColumns()
        let row = recipeListPage.recipeRow(id: first.id)
        XCTAssertTrue(waitUntil { self.selectedRowCount == 1 }, "No recipe row is highlighted")

        let menu = app.buttons.matching(identifier: UIA.recipeDetailMenu).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: Wait.element), "No «…» in the recipe toolbar")
        let barTop = menu.frame.minY

        tapExpand(expecting: Self.collapse)
        assertListGone(row)
        XCTAssertTrue(waitUntil { self.leftColumn.frame.minX < 2 }, "The expanded recipe starts at \(leftColumn.frame.minX), expected 0")
        awaitTwoColumns()
        capture("recipes-landscape-expanded")

        // Another section and back: still expanded.
        app.buttons.matching(identifier: UIA.tabShopping).firstMatch.tap()
        XCTAssertTrue(waitUntil { !self.expandButton.exists }, "«Покупки» did not open")
        app.buttons.matching(identifier: UIA.tabRecipes).firstMatch.tap()
        XCTAssertTrue(expandButton(reading: Self.collapse).waitForExistence(timeout: Wait.element), "A tab switch collapsed the recipe (no «Свернуть»)")
        XCTAssertFalse(listOnScreen, "A tab switch brought the list back")

        tapExpand(expecting: Self.expand)
        XCTAssertTrue(waitUntil { self.listOnScreen }, "«Свернуть» did not bring the list back")
        XCTAssertTrue(waitUntil { row.isSelected || self.selectedRowCount == 1 }, "The open recipe is not highlighted after «Свернуть»")
        assertListWidth(third: true)
        // The recipe bar keeps its own row and its items after «Свернуть» (not squeezed
        // beside the top tab bar, items not in «More»).
        XCTAssertTrue(waitUntil { menu.exists && menu.isHittable }, "«…» is not on the bar after «Свернуть»")
        XCTAssertLessThan(abs(menu.frame.minY - barTop), 2, "The recipe bar moved from \(barTop) to \(menu.frame.minY) after «Свернуть»")
        XCTAssertTrue(expandButton.isHittable, "«Развернуть» is not on the bar after «Свернуть»")
        capture("recipes-landscape-collapsed")

        // The sidebar beside the content: a third of the rest goes to the list (never under 320).
        showSidebar()
        XCTAssertTrue(waitUntil { self.listOnScreen }, "No list column beside the sidebar")
        assertListWidth(third: true, besideSidebar: true)
        XCTAssertFalse(rightColumn.exists, "The recipe beside the sidebar and the list kept two columns")
        capture("recipes-landscape-sidebar")

        tapExpand(expecting: Self.collapse)
        XCTAssertTrue(waitUntil { !self.sidebarShown }, "«Развернуть» kept the sidebar")
        assertListGone(row)
        awaitTwoColumns()
        XCTAssertTrue(waitUntil { self.leftColumn.frame.minX < 2 }, "The expanded recipe starts at \(leftColumn.frame.minX), expected 0")
        capture("recipes-landscape-sidebar-expanded")

        tapExpand(expecting: Self.expand)
        XCTAssertTrue(waitUntil { self.sidebarShown }, "«Свернуть» did not bring the sidebar back")
        XCTAssertTrue(waitUntil { self.listOnScreen && row.exists }, "«Свернуть» did not bring the list back")
    }

    /// FR-018: the open recipe survives rotation. Portrait splits the width in half and the
    /// recipe keeps one column; expanded, it gets two and stays expanded through rotation.
    func testRotationKeepsRecipe() {
        awaitRows()
        let row = recipeListPage.recipeRow(id: second.id)
        if !row.isSelected { row.tap() }
        XCTAssertTrue(waitUntil { row.isSelected }, "«\(second.name)» did not open")
        XCTAssertTrue(recipeTitle(second.name).waitForExistence(timeout: Wait.element), "«\(second.name)» not in the panel")

        rotate(to: .portrait)
        XCTAssertTrue(waitUntil { self.listOnScreen }, "No list column in portrait")
        assertListWidth(third: false)
        XCTAssertTrue(waitUntil { row.isSelected }, "Rotation to portrait lost «\(second.name)»")
        XCTAssertTrue(waitUntil { !self.rightColumn.exists }, "The recipe half kept two columns")
        XCTAssertTrue(expandButton.waitForExistence(timeout: Wait.element), "No «Развернуть» in portrait")
        capture("recipes-portrait")

        tapExpand(expecting: Self.collapse)
        assertListGone(row)
        awaitTwoColumns()
        XCTAssertTrue(recipeTitle(second.name).exists, "Expanding changed the recipe")
        capture("recipes-portrait-expanded")

        rotate(to: .landscapeLeft)
        XCTAssertTrue(expandButton(reading: Self.collapse).waitForExistence(timeout: Wait.element), "Rotation collapsed the recipe (no «Свернуть»)")
        XCTAssertFalse(listOnScreen, "Rotation brought the list back")
        awaitTwoColumns()
        XCTAssertTrue(recipeTitle(second.name).exists, "Rotation back changed the recipe")

        tapExpand(expecting: Self.expand)
        XCTAssertTrue(waitUntil { self.listOnScreen }, "The list column did not come back in landscape")
        XCTAssertTrue(waitUntil { row.isSelected }, "Rotation back lost «\(second.name)»")
        assertListWidth(third: true)
    }

    // MARK: - Collections and the context menu

    /// `#recipes/collection`: the title menu opens a collection with its first recipe;
    /// «Все рецепты» brings the whole list back and keeps the recipe.
    func testCollectionSelection() {
        let collection = TestData.collectionName("E2E iPad Folder")
        awaitRows()
        let firstRow = recipeListPage.recipeRow(id: first.id)
        let secondRow = recipeListPage.recipeRow(id: second.id)
        if firstRow.isSelected {
            // Open the other recipe, so the collection has to switch it.
            secondRow.tap()
            XCTAssertTrue(waitUntil { secondRow.isSelected }, "«\(second.name)» did not open")
        }
        assign(firstRow, toNewCollection: collection)

        openTitleMenu()
        tapMenuItem([collection])
        // The column is rebuilt for the collection: match the title, never read a missing one.
        let collectionTitle = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            UIA.ipadRecipeListTitleMenu,
            collection
        )).firstMatch
        XCTAssertTrue(collectionTitle.waitForExistence(timeout: Wait.element), "The column title is not «\(collection)»")
        XCTAssertTrue(waitUntil { firstRow.exists && firstRow.isSelected }, "The collection did not open its recipe")
        XCTAssertTrue(waitUntil { !secondRow.exists }, "«\(second.name)» is listed in the collection")
        XCTAssertTrue(recipeTitle(first.name).waitForExistence(timeout: Wait.element), "«\(first.name)» not in the panel")
        capture("recipes-collection-landscape")

        openTitleMenu()
        tapMenuItem(["Все рецепты", "All recipes"])
        XCTAssertTrue(waitUntil { secondRow.exists }, "«Все рецепты» did not list every recipe")
        XCTAssertTrue(waitUntil { firstRow.isSelected }, "«Все рецепты» changed the open recipe")
    }

    /// `#recipes/context`: the row menu, «Закрепить» flips to «Открепить».
    func testContextMenu() {
        awaitRows()
        let row = recipeListPage.recipeRow(id: second.id)

        row.press(forDuration: 1.2)
        for labels in [Self.pin, Self.addToCollection, Self.addToShopping, Self.delete] {
            XCTAssertTrue(menuItem(labels).waitForExistence(timeout: Wait.element), "Context menu has no «\(labels[0])»")
        }
        capture("recipes-context-landscape")
        menuItem(Self.pin).tap()

        XCTAssertTrue(waitUntil { !self.menuItem(Self.pin).exists }, "Context menu stayed open")
        row.press(forDuration: 1.2)
        XCTAssertTrue(menuItem(Self.unpin).waitForExistence(timeout: Wait.syncRoundTrip), "«Закрепить» did not pin the recipe")
        XCTAssertFalse(menuItem(Self.pin).exists, "A pinned recipe still offers «Закрепить»")

        menuItem(Self.addToCollection).tap()
        XCTAssertTrue(assignSheetTitle.waitForExistence(timeout: Wait.element), "«В коллекцию» did not open the collection sheet")
        XCTAssertTrue(menuItem(Self.newCollection).exists, "The collection sheet has no «Новая коллекция»")
    }

    // MARK: - Search

    /// `#recipes/search`: the column search filters the column; no match → the empty state.
    func testSearchFiltersColumn() {
        awaitRows()
        let firstRow = recipeListPage.recipeRow(id: first.id)
        let secondRow = recipeListPage.recipeRow(id: second.id)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Wait.element), "No search field in the list column")
        XCTAssertLessThanOrEqual(field.frame.maxX, leftColumn.frame.minX, "The search field is outside the list column")

        field.tap()
        field.typeText("alpha")
        XCTAssertTrue(waitUntil { !secondRow.exists }, "«alpha» kept «\(second.name)»")
        XCTAssertTrue(firstRow.exists, "«alpha» hid «\(first.name)»")
        XCTAssertTrue(listOnScreen, "Search moved the list out of the column")
        capture("recipes-search-landscape")

        field.typeText(" zzqx")
        let empty = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Нет таких рецептов", "No such recipes"])).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: Wait.element), "No empty state for a query without matches")
        XCTAssertFalse(firstRow.exists, "«alpha zzqx» kept «\(first.name)»")
        XCTAssertTrue(leftColumn.exists, "Search closed the open recipe")
    }

    /// The software keyboard shortens the content, not the layout: in portrait the list keeps
    /// half the width beside the recipe (a keyboard-short 834×700 frame used to read as
    /// landscape and squeeze the list to a third, 320 pt), and landscape keeps its third.
    func testKeyboardKeepsTheSplit() {
        awaitRows()
        rotate(to: .portrait)
        XCTAssertTrue(waitUntil { self.listOnScreen }, "No list column in portrait")
        assertListWidth(third: false)
        let portraitWidth = listColumn.frame.width

        raiseKeyboard()
        assertListKeeps(portraitWidth, "portrait")
        capture("recipes-portrait-keyboard")

        rotate(to: .landscapeLeft)
        assertListWidth(third: true)
        let landscapeWidth = listColumn.frame.width
        raiseKeyboard()
        assertListKeeps(landscapeWidth, "landscape")
    }

    // MARK: - Helpers

    private static let expand = ["Развернуть", "Expand"]
    private static let collapse = ["Свернуть", "Collapse"]
    private static let pin = ["Закрепить", "Pin"]
    private static let unpin = ["Открепить", "Unpin"]
    private static let addToCollection = ["В коллекцию", "Add to Collection"]
    private static let addToShopping = ["В\u{00a0}список покупок", "В список покупок", "Add to shopping list"]
    private static let delete = ["Удалить", "Delete"]
    private static let newCollection = ["Новая коллекция", "New collection"]
    /// `IPadLayoutMetrics.sidebarWidth`: the sidebar (272) and its 8 pt inset.
    private static let sidebarWidth: CGFloat = 280

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private var listColumn: XCUIElement { element(UIA.ipadRecipeListColumn) }

    /// The list column on screen. Expanded, it stays in the hierarchy off the leading edge.
    private var listOnScreen: Bool {
        listColumn.exists && listColumn.frame.maxX > 1
    }
    private var leftColumn: XCUIElement { app.scrollViews.matching(identifier: UIA.ipadRecipeDetailLeftColumn).firstMatch }
    private var rightColumn: XCUIElement { app.scrollViews.matching(identifier: UIA.ipadRecipeDetailRightColumn).firstMatch }
    private var expandButton: XCUIElement { app.buttons.matching(identifier: UIA.ipadRecipeExpandButton).firstMatch }
    /// The expand button matched by its label: reading `.label` of a button that is being
    /// rebuilt fails the test at once.
    private func expandButton(reading labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label IN %@",
            UIA.ipadRecipeExpandButton,
            labels
        )).firstMatch
    }
    private var titleMenu: XCUIElement { app.buttons.matching(identifier: UIA.ipadRecipeListTitleMenu).firstMatch }

    private var selectedRowCount: Int {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", UIA.recipeRowPrefix))
            .count
    }

    private func recipeTitle(_ name: String) -> XCUIElement {
        leftColumn.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    private func menuItem(_ labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func awaitRows(file: StaticString = #filePath, line: UInt = #line) {
        for recipe in [first!, second!] {
            XCTAssertTrue(
                recipeListPage.recipeRow(id: recipe.id).waitForExistence(timeout: Wait.syncRoundTrip),
                "Row «\(recipe.name)» missing",
                file: file,
                line: line
            )
        }
    }

    private func awaitTwoColumns(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(leftColumn.waitForExistence(timeout: Wait.firstPaint), "No left recipe column", file: file, line: line)
        XCTAssertTrue(rightColumn.exists, "No steps column", file: file, line: line)
    }

    /// The toolbar keeps «…» and «Изменить» on the bar, not in the system overflow.
    private func assertToolbarFits(_ state: String, file: StaticString = #filePath, line: UInt = #line) {
        let menu = app.buttons.matching(identifier: UIA.recipeDetailMenu).firstMatch
        let edit = app.buttons.matching(identifier: UIA.recipeDetailEdit).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: Wait.element), "«…» missing (\(state))", file: file, line: line)
        XCTAssertTrue(waitUntil { menu.isHittable }, "«…» is not on the bar (\(state))", file: file, line: line)
        XCTAssertTrue(edit.exists && edit.isHittable, "«Изменить» is not on the bar (\(state))", file: file, line: line)
        XCTAssertGreaterThan(edit.frame.minX, leftColumn.frame.minX, "Toolbar items sit over the list (\(state))", file: file, line: line)
    }

    /// The list column is a third of the content in landscape, half in portrait (never
    /// under 320); the recipe panel starts after its 1 pt divider. Beside the sidebar the
    /// content is the rest of the window, and the column runs on under the floating sidebar,
    /// so its trailing edge tells its width.
    private func assertListWidth(
        third: Bool,
        besideSidebar: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch.frame.width
        let leading: CGFloat = besideSidebar ? Self.sidebarWidth : 0
        let content = window - leading
        let share: CGFloat = third ? 1.0 / 3.0 : 1.0 / 2.0
        let expected = max(320, ((content - 1) * share).rounded())
        XCTAssertTrue(
            waitUntil { abs(self.listColumn.frame.maxX - leading - expected) <= 2 },
            "The list column ends at \(listColumn.frame.maxX) in a \(window) pt window, expected \(leading + expected)",
            file: file,
            line: line
        )
        let panel = leftColumn.exists ? leftColumn.frame.minX : nil
        if let panel {
            XCTAssertLessThan(
                abs(panel - (leading + expected + 1)),
                2,
                "The recipe starts at \(panel), expected \(leading + expected + 1)",
                file: file,
                line: line
            )
        }
    }

    /// Expanded: the list column is off screen and nothing of it is left to reach — no
    /// rows, no «+», no search field (VoiceOver, Full Keyboard Access).
    private func assertListGone(_ row: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            waitUntil { !self.listOnScreen },
            "«Развернуть» kept the list column on screen at \(listColumn.frame)",
            file: file,
            line: line
        )
        XCTAssertTrue(waitUntil { !row.exists }, "A row of the hidden list is still in the tree", file: file, line: line)
        XCTAssertEqual(rowCount, 0, "Rows of the hidden list are still in the tree", file: file, line: line)
        XCTAssertFalse(recipeListPage.addButton.exists, "«+» of the hidden list is still in the tree", file: file, line: line)
        XCTAssertEqual(app.searchFields.count, 0, "The search field of the hidden list is still in the tree", file: file, line: line)
    }

    private var rowCount: Int {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", UIA.recipeRowPrefix)).count
    }

    /// Taps «Развернуть» / «Свернуть» and waits for the button to read `labels`.
    private func tapExpand(expecting labels: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(expandButton.waitForExistence(timeout: Wait.element), "No expand button", file: file, line: line)
        expandButton.tap()
        XCTAssertTrue(expandButton(reading: labels).waitForExistence(timeout: Wait.element), "The expand button does not read «\(labels[0])»", file: file, line: line)
    }

    /// A tap on the column search brings up the software keyboard (the simulator runs with
    /// the hardware keyboard disconnected).
    private func raiseKeyboard(file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { return }
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Wait.element), "No search field in the list column", file: file, line: line)
        field.tap()
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: Wait.element),
            "No software keyboard after a tap on the search (is a hardware keyboard connected to the simulator?)",
            file: file,
            line: line
        )
    }

    /// With the keyboard up the list column keeps `width` (±1 pt) and the recipe stays beside
    /// it, sampled through the keyboard animation and the relayout after it.
    private func assertListKeeps(_ width: CGFloat, _ state: String, file: StaticString = #filePath, line: UInt = #line) {
        let end = Date().addingTimeInterval(2.5)
        repeat {
            let now = listColumn.frame
            guard listOnScreen, abs(now.width - width) <= 1 else {
                XCTFail("With the keyboard (\(state)) the list column is \(now), expected \(width) pt wide", file: file, line: line)
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < end
        XCTAssertTrue(app.keyboards.firstMatch.exists, "The keyboard went away (\(state))", file: file, line: line)
        XCTAssertTrue(expandButton.exists, "No «Развернуть» with the keyboard (\(state)): the list is not beside the recipe", file: file, line: line)
        XCTAssertGreaterThan(
            expandButton.frame.minX,
            listColumn.frame.maxX,
            "«Развернуть» is not in the recipe panel with the keyboard (\(state))",
            file: file,
            line: line
        )
    }

    private func openTitleMenu() {
        XCTAssertTrue(titleMenu.waitForExistence(timeout: Wait.element), "No collection menu in the column title")
        titleMenu.tap()
    }

    private func tapMenuItem(_ labels: [String]) {
        let item = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@ AND identifier != %@", labels, UIA.ipadRecipeListTitleMenu))
            .firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: Wait.syncRoundTrip), "Title menu has no «\(labels[0])»")
        item.tap()
    }

    private var assignSheetTitle: XCUIElement {
        app.navigationBars.matching(NSPredicate(
            format: "identifier IN %@",
            ["Добавить в\u{00a0}коллекцию", "Добавить в коллекцию", "Add to collection"]
        )).firstMatch
    }

    /// «В коллекцию» from the row menu: a new collection in the sheet (checked on
    /// creation), then the sheet closes and saves the membership.
    private func assign(_ row: XCUIElement, toNewCollection collectionName: String) {
        row.press(forDuration: 1.2)
        let item = menuItem(Self.addToCollection)
        XCTAssertTrue(item.waitForExistence(timeout: Wait.element), "Context menu has no «В коллекцию»")
        item.tap()
        XCTAssertTrue(assignSheetTitle.waitForExistence(timeout: Wait.element), "Collection sheet did not open")

        let newRow = menuItem(Self.newCollection)
        XCTAssertTrue(newRow.waitForExistence(timeout: Wait.element), "No «Новая коллекция» in the sheet")
        // The row reacts to its icon and words only (a plain button): tap the words.
        newRow.staticTexts.firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Wait.element), "No collection name field")
        field.tap()
        field.typeText(collectionName + "\n")

        let sheetRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", collectionName)).firstMatch
        XCTAssertTrue(sheetRow.waitForExistence(timeout: Wait.syncRoundTrip), "Collection «\(collectionName)» was not created")

        // A form sheet on the iPad: a tap on the dimmed list outside it closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.95)).tap()
        XCTAssertTrue(waitUntil { !self.assignSheetTitle.exists }, "The collection sheet did not close")
    }

    private func rotate(to orientation: UIDeviceOrientation, file: StaticString = #filePath, line: UInt = #line) {
        XCUIDevice.shared.orientation = orientation
        let wantsLandscape = orientation.isLandscape
        XCTAssertTrue(
            waitUntil {
                let frame = self.app.windows.firstMatch.frame
                return wantsLandscape == (frame.width > frame.height)
            },
            "The app did not turn to \(wantsLandscape ? "landscape" : "portrait")",
            file: file,
            line: line
        )
        if wantsLandscape { hideSidebarIfShown() }
    }

    /// The system brings the landscape sidebar back after a rotation even when the app
    /// launched with it hidden. Its own toggle (`ToggleSidebar`, the top bar has
    /// `ToggleSideBar`) is the sign it is shown.
    private func hideSidebarIfShown() {
        let toggle = app.buttons.matching(identifier: "ToggleSidebar").firstMatch
        guard toggle.waitForExistence(timeout: 3), toggle.isHittable else { return }
        toggle.tap()
        XCTAssertTrue(waitUntil { !self.sidebarShown }, "Sidebar did not hide")
    }

    /// The sidebar's own toggle (`ToggleSidebar`) is on screen only while it is shown.
    private var sidebarShown: Bool {
        let toggle = app.buttons.matching(identifier: "ToggleSidebar").firstMatch
        return toggle.exists && toggle.isHittable
    }

    /// The top bar toggle (`ToggleSideBar`) brings the sidebar beside the content.
    private func showSidebar(file: StaticString = #filePath, line: UInt = #line) {
        let toggle = app.buttons.matching(identifier: "ToggleSidebar").firstMatch
        if toggle.waitForExistence(timeout: 3), toggle.isHittable { return }
        let topBarToggle = app.buttons.matching(identifier: "ToggleSideBar").firstMatch
        XCTAssertTrue(topBarToggle.waitForExistence(timeout: Wait.firstPaint), "No sidebar toggle in the top bar", file: file, line: line)
        topBarToggle.tap()
        XCTAssertTrue(waitUntil { self.sidebarShown }, "Sidebar did not show", file: file, line: line)
    }

    private func capture(_ name: String) {
        guard ProcessInfo.processInfo.environment["E2E_SCREENSHOTS"] == "1" else { return }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval = Wait.element, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
