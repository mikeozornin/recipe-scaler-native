import notify
import UIKit
import XCTest

/// Spec coverage: specs/081-ipad-adaptation/spec.md, US7 (multitasking in one window),
/// T049, FR-018, FR-030, SC-005.
///
/// iPad only. One window that changes width while the app runs, as Split View and Stage
/// Manager do: the full window → ⅔ → the 680 pt regular minimum → compact ½ → ⅓ →
/// 320 → back. The simulator cannot script a real resize, so the app runs with
/// `-DebugWindowWidthLive=1` and the test sets the root width over a Darwin notification
/// (`DebugWindowWidthChannel` in the app): the root narrows and the size class follows the
/// width, the same view tree throughout. At every width the open recipe and the collection
/// it was opened from must still be there (SC-005), and the layout must match
/// `IPadLayoutPolicy` (layout.md §Матрица приёмки): the list column, its width, one or two
/// recipe columns, the top bar or the phone bottom bar.
///
/// On iPadOS 26.2+ that is the adaptive shell. Below it the same walk checks the old path
/// (spec.md Q1, T051): the system tab bar and no sidebar, with the same split, recipe
/// columns, panel and sheet.
///
/// What the stand-in cannot show: the system's own window chrome, the Slide Over and Split
/// View handles, the real size class of a 13″ ½ window (regular at 678 pt), the sheets
/// (presented by the full window). Those stay manual device checks (T049).
///
/// `verify-ipad-layout.sh --matrix` runs the spec with `IPAD_MATRIX_SHOTS=1` (passed as
/// `TEST_RUNNER_IPAD_MATRIX_SHOTS`): at each checked width the test prints
/// `IPAD_MATRIX_SHOT <n> <name>`, the script takes a `simctl io screenshot` (the XCTest one is
/// a cropped portrait buffer in landscape) and answers over `ru.recipescaler.debug.matrix-shot`,
/// then the test prints `IPAD_MATRIX_SHOT_TAKEN <n>`. `IPAD_MATRIX_ROW` lines record the
/// measured layout of every step. Test users only: no real data on the screenshots.
final class IPadMultitaskingSpec: BaseTestCase {
    private var first: SeedClient.CreatedRecipe!
    private var second: SeedClient.CreatedRecipe!
    private var collection = ""
    private var driver: WindowWidthDriver!

    /// Marker numbers are unique over the whole run: the script checks every one was answered.
    private static var shotCount: UInt64 = 0
    private static let fixtureQuestion = ["Соус свернулся", "My sauce split"]

    @MainActor
    override func setUp() async throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "iPad multitasking (spec 081) — iPad only"
        )
        driver = WindowWidthDriver()
        driver.set(nil)
        XCUIDevice.shared.orientation = startsInPortrait ? .portrait : .landscapeLeft
        try await super.setUp()
        rotate(to: startsInPortrait ? .portrait : .landscapeLeft)
    }

    @MainActor
    override func tearDown() async throws {
        driver?.set(nil)
        XCUIDevice.shared.orientation = .portrait
        try await super.tearDown()
    }

    private var startsInPortrait: Bool { name.contains("Portrait") }
    private var keepsSidebar: Bool { name.contains("WithSidebar") }
    /// The sidebar shell; below iPadOS 26.2 the system tab bar has no sidebar (Q1).
    private var hasSidebarShell: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 2, patchVersion: 0)
        )
    }

    override func extraLaunchArguments() -> [String] {
        var args = ["-DebugWindowWidthLive=1"]
        args.append(name.contains("testShopping") ? "-OpenTab=shopping" : "-OpenTab=recipes")
        args.append(keepsSidebar ? "-IPadSidebarShown=1" : "-IPadSidebarHidden=1")
        if name.contains("Assistant") {
            args.append("-ScreenshotAssistantFixture=1")
        }
        return args
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

    // MARK: - Recipes

    /// `#recipes/tabs`, landscape: the window shrinks through every threshold of the matrix
    /// and grows back, the recipe and its collection stay open all the way.
    func testRecipesWidthsLandscape() {
        openRecipeInCollection()
        walk(state: "recipes-tabs", widths: widths(landscape: true))
    }

    /// `#recipes/tabs`, portrait: the half-and-half split, then the compact ⅔ / ½ / ⅓ windows.
    func testRecipesWidthsPortrait() {
        openRecipeInCollection()
        walk(state: "recipes-tabs", widths: widths(landscape: false))
    }

    /// `#recipes/sidebar`, landscape: the sidebar beside the content leaves no room for the
    /// list at ⅔ (the recipe is pushed), compact hides the sidebar, regular brings the shell back.
    /// Below iPadOS 26.2 the launch argument must bring no sidebar, so the split is exact.
    func testRecipesWidthsLandscapeWithSidebar() {
        openRecipeInCollection()
        walk(state: "recipes-sidebar", widths: widths(landscape: true), exactLayout: !hasSidebarShell)
    }

    // MARK: - Assistant

    /// `#assistant/chat`: the panel beside the recipe turns into the phone sheet in a compact
    /// window and back into the panel; the chat, the recipe and the collection survive. With the
    /// sidebar beside the panel the list column stays hidden too (FR-022).
    func testAssistantWidthsLandscape() {
        openRecipeInCollection()
        openPanelFromTopBar()
        let full = windowWidth
        var steps: [CGFloat?] = [nil, 776, 680, 679, 400, 776, nil]
        if full > 1300 { steps.insert(1194, at: 1) }
        for (index, width) in steps.enumerated() {
            resize(to: width)
            let compact = (width ?? full) < Self.regularMinWidth
            if compact {
                XCTAssertTrue(waitUntil(timeout: Wait.firstPaint) { !self.inspector.exists }, "The panel stayed at \(label(width))")
                XCTAssertTrue(
                    waitUntil(timeout: Wait.firstPaint) { self.assistantPage.sheet.exists && !self.inspectorClose.exists },
                    "No assistant sheet at \(label(width))"
                )
            } else {
                XCTAssertTrue(inspector.waitForExistence(timeout: Wait.firstPaint), "No assistant panel at \(label(width))")
                XCTAssertEqual(inspector.frame.width, 340, accuracy: 2, "The panel is \(inspector.frame.width) pt at \(label(width))")
            }
            XCTAssertTrue(waitUntil { self.fixtureQuestions.count == 1 }, "The chat is not shown once at \(label(width))")
            if !compact {
                assertRecipeOpen(first.name, step: label(width))
            }
            record("assistant-chat", width: width, step: index)
            shot("assistant-chat", width: width, step: index)
            if !compact {
                XCTAssertFalse(listOnScreen, "The list column is beside the panel at \(label(width)) (FR-022)")
            }
        }
        if hasSidebarShell {
            // The sidebar beside the panel (the system also brings it back after a compact
            // window): the recipe keeps the content, still no list column.
            showSidebarFromTopBar()
            assertRecipeOpen(first.name, step: "the sidebar beside the panel")
            if listColumn.exists {
                print("IPAD_MATRIX_NOTE the hidden list column ends at \(Int(listColumn.frame.maxX.rounded())) pt, beside the sidebar")
                fflush(stdout)
            }
            record("assistant-sidebar", width: nil, step: steps.count)
            shot("assistant-sidebar", width: nil, step: steps.count)
            XCTAssertFalse(listOnScreen, "The list column is beside the panel and the sidebar (FR-022)")
        }
        // Closed, the panel gives the list column back: the collection is still selected.
        inspectorClose.tap()
        XCTAssertTrue(waitUntil { !self.inspector.exists }, "× did not close the panel")
        assertCollectionAndRecipe(step: "after the panel")
    }

    // MARK: - Shopping

    /// `#shopping/recipe`: the readable page and its toolbar through the widths; the section,
    /// the list and its item stay.
    func testShoppingWidthsLandscape() {
        let item = TestData.shoppingItemLabel("E2E iPad")
        shoppingListPage.awaitReady().addManualItem(item)
        let row = shoppingListPage.row(label: item)
        XCTAssertTrue(row.waitForExistence(timeout: Wait.syncRoundTrip), "Added item missing")
        dismissKeyboard()
        for (index, width) in widths(landscape: true).enumerated() {
            resize(to: width)
            let compact = (width ?? windowWidth) < Self.regularMinWidth
            // Back at the whole window after a compact one the system shows the sidebar again,
            // and «Покупки» is its row, not a top tab.
            if !compact { hideSidebarIfShown() }
            XCTAssertTrue(waitUntil { self.bottomBar == compact }, "\(compact ? "No phone bottom bar" : "No top bar") at \(label(width))")
            XCTAssertTrue(shoppingListPage.root.waitForExistence(timeout: Wait.element), "The shopping list is gone at \(label(width))")
            XCTAssertTrue(waitUntil { row.exists }, "The item is gone at \(label(width))")
            XCTAssertTrue(waitUntil { self.tab(UIA.tabShopping).isSelected }, "«Покупки» is no longer selected at \(label(width))")
            // `shopping_list` names the whole screen with its margins; the add field spans the
            // page's row, so it shows the page width.
            let page = shoppingListPage.addField.frame
            if !compact {
                XCTAssertLessThanOrEqual(page.width, 721, "The shopping page row is \(page.width) pt at \(label(width)), expected ≤ 720")
            }
            XCTAssertLessThanOrEqual(page.maxX, appliedWidth + 1, "The shopping page runs past the window at \(label(width))")
            record("shopping-recipe", width: width, step: index)
            shot("shopping-recipe", width: width, step: index)
        }
    }

    // MARK: - The walk

    private static let regularMinWidth: CGFloat = 680

    /// The checked widths, `nil` = the whole window. layout.md §Матрица приёмки: ⅔ 776, ½ 582,
    /// ⅓ 388 in landscape; ⅔ 536, ½ 402, ⅓ 320 in portrait (11″). Other screens take the same
    /// shares. The 720 pt two-column panel and the 680 pt regular minimum are the thresholds.
    private func widths(landscape: Bool) -> [CGFloat?] {
        let full = windowWidth
        let shares: [CGFloat] = landscape ? [0.65, 0.4874, 0.325] : [0.643, 0.482, 0.3837]
        let split = shares.map { max(320, (full * $0).rounded()) }
        var steps: [CGFloat?] = [nil]
        if landscape { steps.append(1000) }
        steps += [split[0], 720, 700, 680, 679, split[1], split[2], 320, split[1], split[0], nil]
        // Thresholds wider than the window are not windows of this screen.
        return steps.filter { $0 == nil || $0! < full }
    }

    /// Sets each width and checks the layout, the recipe and the collection at it.
    /// `exactLayout`: the widths of the list column and the recipe columns are checked
    /// against `IPadLayoutPolicy`; with the sidebar beside the content only the kind of
    /// layout is (the sidebar's own width and folding are the system's).
    private func walk(state: String, widths: [CGFloat?], exactLayout: Bool = true) {
        for (index, width) in widths.enumerated() {
            resize(to: width)
            let compact = (width ?? windowWidth) < Self.regularMinWidth
            if !compact, !keepsSidebar { hideSidebarIfShown() }
            if !hasSidebarShell {
                XCTAssertFalse(sidebarShown, "A sidebar below iPadOS 26.2 at \(label(width))")
            }
            XCTAssertTrue(
                waitUntil(timeout: Wait.firstPaint) { self.bottomBar == compact },
                "\(compact ? "No phone bottom bar" : "No top bar or sidebar") at \(label(width))"
            )
            if compact {
                assertPhoneStack(step: label(width))
            } else if exactLayout {
                assertSplit(step: label(width))
            } else {
                assertRecipeOpen(first.name, step: label(width))
            }
            if !compact { assertCollectionShown(step: label(width)) }
            record(state, width: width, step: index)
            shot(state, width: width, step: index)
        }
        assertCollectionAndRecipe(step: "the end of the walk")
    }

    /// The split matches `IPadLayoutPolicy.resolve` for the content of this width: the list
    /// column of the policy's width beside a recipe of 320 or more, else no list; two recipe
    /// columns from a 720 pt panel, the left one `min(400, panel − 1 − 320)`.
    private func assertSplit(step: String, file: StaticString = #filePath, line: UInt = #line) {
        let content = appliedWidth
        let candidates = expectedLayouts(contentWidth: content)
        XCTAssertTrue(
            waitUntil(timeout: Wait.firstPaint) { self.matchingLayout(candidates) != nil },
            "At \(step) the layout is list \(listOnScreen ? "\(listColumn.frame.maxX)" : "none"), "
                + "\(rightColumn.exists ? "two" : "one") recipe column(s); the policy allows "
                + candidates.map { $0.listShown ? "list \($0.listWidth) + \($0.twoColumns ? "two" : "one")" : "no list + \($0.twoColumns ? "two" : "one")" }
                .joined(separator: " or "),
            file: file,
            line: line
        )
        guard let layout = matchingLayout(candidates) else { return }
        if layout.listShown {
            XCTAssertTrue(waitUntil { self.firstRow.exists && self.firstRow.isSelected }, "«\(first.name)» is not selected at \(step)", file: file, line: line)
        }
        if layout.twoColumns {
            let left = min(400, layout.detailWidth - 1 - 320)
            XCTAssertEqual(leftColumn.frame.width, left, accuracy: 2, "The left recipe column at \(step)", file: file, line: line)
        }
        assertRecipeOpen(first.name, step: step, file: file, line: line)
    }

    /// The candidate the screen shows: the list column (or none) and the number of recipe columns.
    private func matchingLayout(_ candidates: [ExpectedLayout]) -> ExpectedLayout? {
        let shown = listOnScreen
        let listEnd = listColumn.frame.maxX
        let two = leftColumn.exists && rightColumn.exists
        let one = !rightColumn.exists && recipeMenu.exists
        return candidates.first { layout in
            guard layout.listShown == shown, layout.twoColumns ? two : one else { return false }
            return !shown || abs(listEnd - layout.listWidth) <= 2
        }
    }

    /// The phone stack: the recipe on top, «Назад» to the collection it was opened from.
    private func assertPhoneStack(step: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(listOnScreen, "A list column in the compact window at \(step)", file: file, line: line)
        XCTAssertFalse(rightColumn.exists, "Two recipe columns in the compact window at \(step)", file: file, line: line)
        assertRecipeOpen(first.name, step: step, file: file, line: line)
        XCTAssertTrue(
            waitUntil { self.backButton.exists },
            "No «Назад» over the recipe at \(step): the stack lost the collection",
            file: file,
            line: line
        )
        XCTAssertTrue(
            backButton.label.contains(collection),
            "«Назад» reads «\(backButton.label)» at \(step), expected the collection «\(collection)»",
            file: file,
            line: line
        )
    }

    /// The recipe title in the content and the recipe toolbar.
    private func assertRecipeOpen(_ name: String, step: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            waitUntil(timeout: Wait.firstPaint) { self.recipeTitleShown(name) },
            "«\(name)» is not open at \(step)",
            file: file,
            line: line
        )
        XCTAssertTrue(recipeMenu.waitForExistence(timeout: Wait.element), "No recipe toolbar «…» at \(step)", file: file, line: line)
    }

    /// The collection in the list column title, or «Назад» to it from the pushed recipe.
    private func assertCollectionShown(step: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            waitUntil(timeout: Wait.firstPaint) { self.collectionTitle.exists || self.backButtonNamesCollection },
            "The collection «\(collection)» is gone at \(step)",
            file: file,
            line: line
        )
    }

    /// Back in the whole window: the collection still selected, its recipe still open.
    private func assertCollectionAndRecipe(step: String, file: StaticString = #filePath, line: UInt = #line) {
        assertCollectionShown(step: step, file: file, line: line)
        assertRecipeOpen(first.name, step: step, file: file, line: line)
        if listOnScreen {
            XCTAssertTrue(waitUntil { !self.secondRow.exists }, "«\(second.name)» is listed in the collection at \(step)", file: file, line: line)
        }
    }

    // MARK: - Layout policy mirror

    private struct ExpectedLayout {
        let listShown: Bool
        let listWidth: CGFloat
        let detailWidth: CGFloat
        let twoColumns: Bool
    }

    /// `IPadLayoutPolicy.resolve` without the panel, the sidebar and the keyboard: the list is
    /// half of a content narrower than the window is tall (portrait, and the ⅔ landscape
    /// window), a third otherwise, at least 320, and shows only beside a recipe of 320 or
    /// more; two recipe columns from a 720 pt panel. A list of one share, kept as an array so
    /// a screen with another rule shows every candidate in the failure.
    private func expectedLayouts(contentWidth: CGFloat) -> [ExpectedLayout] {
        let shares: [CGFloat] = [windowHeight > contentWidth ? 1.0 / 2.0 : 1.0 / 3.0]
        return shares.map { share in
            let list = max(320, ((contentWidth - 1) * share).rounded())
            let fits = contentWidth - list - 1 >= 320
            let detail = fits ? contentWidth - list - 1 : contentWidth
            return ExpectedLayout(listShown: fits, listWidth: list, detailWidth: detail, twoColumns: detail >= 720)
        }
    }

    // MARK: - Width channel

    /// Sets the root width (`nil` = the whole window) and waits until the app's root has it.
    private func resize(to width: CGFloat?, file: StaticString = #filePath, line: UInt = #line) {
        driver.set(width)
        let want = width ?? windowWidth
        XCTAssertTrue(
            waitUntil(timeout: Wait.firstPaint) { abs(self.driver.applied - want) < 1 },
            "The app root did not take \(want) pt (it reports \(driver.applied))",
            file: file,
            line: line
        )
    }

    private var appliedWidth: CGFloat { driver.applied }
    private var windowWidth: CGFloat { app.windows.firstMatch.frame.width }
    private var windowHeight: CGFloat { app.windows.firstMatch.frame.height }

    private func label(_ width: CGFloat?) -> String {
        width.map { "\(Int($0)) pt" } ?? "the whole window (\(Int(windowWidth)) pt)"
    }

    /// `<step>-<state>-<orientation>-<width>of<window>`, as the files of `verify-ipad-layout.sh`.
    private func shotName(_ state: String, width: CGFloat?, step: Int) -> String {
        let orientation = windowWidth > windowHeight ? "landscape" : "portrait"
        let full = Int(windowWidth)
        let window = width.map { "\(Int($0))of\(full)" } ?? "full\(full)"
        return String(format: "%02d", step) + "-\(state)-\(orientation)-\(window)"
    }

    /// One line of the measured layout per step, for the matrix table of the run.
    private func record(_ state: String, width: CGFloat?, step: Int) {
        let list = listOnScreen ? "\(Int(listColumn.frame.maxX.rounded()))" : "-"
        let columns = rightColumn.exists ? "2" : (recipeMenu.exists ? "1" : "-")
        let left = leftColumn.exists ? "\(Int(leftColumn.frame.width.rounded()))" : "-"
        let panel = inspector.exists ? "\(Int(inspector.frame.width.rounded()))" : "-"
        let line = [
            "IPAD_MATRIX_ROW \(shotName(state, width: width, step: step))",
            "root=\(Int(appliedWidth))",
            "bar=\(bottomBar ? "bottom" : "top")",
            "sidebar=\(sidebarShown ? "shown" : "hidden")",
            "list=\(list)",
            "columns=\(columns)",
            "left=\(left)",
            "panel=\(panel)",
        ].joined(separator: " ")
        print(line)
        fflush(stdout)
    }

    /// Asks `verify-ipad-layout.sh --matrix` for a host screenshot and waits for it.
    private func shot(_ state: String, width: CGFloat?, step: Int, file: StaticString = #filePath, line: UInt = #line) {
        guard ProcessInfo.processInfo.environment["IPAD_MATRIX_SHOTS"] == "1" else { return }
        Self.shotCount += 1
        let number = Self.shotCount
        print("IPAD_MATRIX_SHOT \(number) \(shotName(state, width: width, step: step))")
        fflush(stdout)
        XCTAssertTrue(
            waitUntil(timeout: 60) { self.driver.shotAnswer >= number },
            "The host took no screenshot \(number)",
            file: file,
            line: line
        )
        print("IPAD_MATRIX_SHOT_TAKEN \(number)")
        fflush(stdout)
    }

    // MARK: - Recipes helpers

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private var firstRow: XCUIElement { recipeListPage.recipeRow(id: first.id) }
    private var secondRow: XCUIElement { recipeListPage.recipeRow(id: second.id) }
    private var listColumn: XCUIElement { element(UIA.ipadRecipeListColumn) }
    /// Hidden or expanded, the list column waits off the leading edge of the content, emptied
    /// (`IPadRecipesSplitView.split`). Beside a sidebar that edge is the sidebar's, right of
    /// the window's, so the column counts only with its collection title in it.
    private var listOnScreen: Bool { listColumn.exists && listColumn.frame.maxX > 1 && collectionTitle.exists }
    private var leftColumn: XCUIElement { app.scrollViews.matching(identifier: UIA.ipadRecipeDetailLeftColumn).firstMatch }
    private var rightColumn: XCUIElement { app.scrollViews.matching(identifier: UIA.ipadRecipeDetailRightColumn).firstMatch }
    private var recipeMenu: XCUIElement { app.buttons.matching(identifier: UIA.recipeDetailMenu).firstMatch }
    private var titleMenu: XCUIElement { app.buttons.matching(identifier: UIA.ipadRecipeListTitleMenu).firstMatch }

    /// The column title names the collection: a menu in the top bar, a plain title beside the sidebar.
    private var collectionTitle: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@ AND label CONTAINS %@",
            [UIA.ipadRecipeListTitle, UIA.ipadRecipeListTitleMenu],
            collection
        )).firstMatch
    }

    private var backButton: XCUIElement { app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch }
    private var backButtonNamesCollection: Bool { backButton.exists && backButton.label.contains(collection) }

    /// The recipe title outside the list column (a row carries the same name).
    private func recipeTitleShown(_ name: String) -> Bool {
        let listEnd = listOnScreen ? listColumn.frame.maxX : 0
        let titles = app.staticTexts.matching(NSPredicate(format: "label == %@", name))
        for index in 0..<titles.count {
            let title = titles.element(boundBy: index)
            if title.exists, title.frame.minX >= listEnd, title.frame.maxX <= appliedWidth + 1 { return true }
        }
        return false
    }

    /// The tab bar is at the bottom: the phone shell of a compact window.
    private var bottomBar: Bool {
        let recipes = tab(UIA.tabRecipes)
        let shopping = tab(UIA.tabShopping)
        let anyTab = recipes.exists ? recipes : shopping
        guard anyTab.exists else { return false }
        return anyTab.frame.midY > windowHeight / 2
    }

    private func tab(_ id: String) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    /// Makes a collection with the first recipe («В коллекцию» in the row menu) and opens it,
    /// so the first recipe is open in it. Beside the sidebar the collection is its row.
    private func openRecipeInCollection() {
        collection = TestData.collectionName("E2E Window")
        XCTAssertTrue(firstRow.waitForExistence(timeout: Wait.syncRoundTrip), "Row «\(first.name)» missing")
        XCTAssertTrue(secondRow.waitForExistence(timeout: Wait.syncRoundTrip), "Row «\(second.name)» missing")
        if firstRow.isSelected {
            secondRow.tap()
            XCTAssertTrue(waitUntil { self.secondRow.isSelected }, "«\(second.name)» did not open")
        }
        assign(firstRow, toNewCollection: collection)

        if keepsSidebar, hasSidebarShell {
            let row = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                UIA.ipadSidebarCollectionPrefix,
                collection
            )).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: Wait.firstPaint), "Collection «\(collection)» missing from the sidebar")
            row.tap()
        } else {
            XCTAssertTrue(titleMenu.waitForExistence(timeout: Wait.element), "No collection menu in the column title")
            titleMenu.tap()
            let item = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@ AND identifier != %@", collection, UIA.ipadRecipeListTitleMenu))
                .firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: Wait.syncRoundTrip), "The title menu has no «\(collection)»")
            item.tap()
        }
        XCTAssertTrue(collectionTitle.waitForExistence(timeout: Wait.firstPaint), "The column title is not «\(collection)»")
        XCTAssertTrue(waitUntil { self.firstRow.exists && self.firstRow.isSelected }, "The collection did not open «\(first.name)»")
        assertRecipeOpen(first.name, step: "the start")
    }

    /// «В коллекцию» from the row menu: a new collection in the sheet (checked on creation),
    /// then a tap outside closes the sheet and saves the membership.
    private func assign(_ row: XCUIElement, toNewCollection name: String) {
        row.press(forDuration: 1.2)
        let item = app.buttons.matching(NSPredicate(format: "label IN %@", ["В коллекцию", "Add to Collection"])).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: Wait.element), "The row menu has no «В коллекцию»")
        item.tap()
        let sheetTitle = app.navigationBars.matching(NSPredicate(
            format: "identifier IN %@",
            ["Добавить в\u{00a0}коллекцию", "Добавить в коллекцию", "Add to collection"]
        )).firstMatch
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: Wait.element), "The collection sheet did not open")

        let newRow = app.buttons.matching(NSPredicate(format: "label IN %@", ["Новая коллекция", "New collection"])).firstMatch
        XCTAssertTrue(newRow.waitForExistence(timeout: Wait.element), "No «Новая коллекция» in the sheet")
        newRow.staticTexts.firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Wait.element), "No collection name field")
        field.tap()
        field.typeText(name + "\n")
        let created = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: Wait.syncRoundTrip), "Collection «\(name)» was not created")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.95)).tap()
        XCTAssertTrue(waitUntil { !sheetTitle.exists }, "The collection sheet did not close")
    }

    // MARK: - Assistant helpers

    /// The panel, by its bar with ×.
    private var inspector: XCUIElement {
        app.navigationBars.containing(.button, identifier: UIA.ipadAssistantInspectorCloseButton).firstMatch
    }
    private var inspectorClose: XCUIElement {
        app.buttons.matching(identifier: UIA.ipadAssistantInspectorCloseButton).firstMatch
    }
    private var fixtureQuestions: XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@",
            Self.fixtureQuestion[0],
            Self.fixtureQuestion[1]
        ))
    }

    private func openPanelFromTopBar() {
        let assistant = tab(UIA.assistantTab)
        XCTAssertTrue(assistant.waitForExistence(timeout: Wait.element), "«Ассистент» missing from the top bar")
        assistant.tap()
        XCTAssertTrue(inspector.waitForExistence(timeout: Wait.element), "The «Ассистент» tab did not open the panel")
        XCTAssertTrue(fixtureQuestions.firstMatch.waitForExistence(timeout: Wait.element), "The panel shows no chat")
    }

    // MARK: - Window helpers

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
        if wantsLandscape, !keepsSidebar { hideSidebarIfShown() }
    }

    /// The sidebar's own toggle (`ToggleSidebar`) is on screen only while it is shown.
    private var sidebarShown: Bool {
        let toggle = app.buttons.matching(identifier: "ToggleSidebar").firstMatch
        return toggle.exists && toggle.isHittable
    }

    /// The system brings the landscape sidebar back after a rotation or a size class change
    /// even when the app launched with it hidden.
    private func hideSidebarIfShown() {
        let toggle = app.buttons.matching(identifier: "ToggleSidebar").firstMatch
        guard toggle.waitForExistence(timeout: 2), toggle.isHittable else { return }
        print("IPAD_MATRIX_NOTE the system showed the sidebar again at \(Int(appliedWidth)) pt")
        fflush(stdout)
        toggle.tap()
        XCTAssertTrue(waitUntil { !self.sidebarShown }, "Sidebar did not hide")
    }

    /// The top bar's toggle is `ToggleSideBar`; the system may have shown the sidebar already.
    private func showSidebarFromTopBar() {
        guard !sidebarShown else { return }
        let toggle = app.buttons.matching(identifier: "ToggleSideBar").firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: Wait.firstPaint), "No sidebar toggle in the top bar")
        toggle.tap()
        XCTAssertTrue(waitUntil { self.sidebarShown }, "Sidebar did not show")
    }

    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        _ = waitUntil { !self.app.keyboards.firstMatch.exists }
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval = Wait.element, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

/// The test side of the app's `DebugWindowWidthChannel` (DEBUG, `-DebugWindowWidthLive=1`),
/// and the answer channel of `verify-ipad-layout.sh --matrix`. Darwin notification states
/// live while a process holds the name, so every name is registered for the whole test.
private final class WindowWidthDriver {
    private static let widthName = "ru.recipescaler.debug.window-width"
    private static let appliedName = "ru.recipescaler.debug.window-width.applied"
    private static let shotName = "ru.recipescaler.debug.matrix-shot"

    private var widthToken = NOTIFY_TOKEN_INVALID
    private var appliedToken = NOTIFY_TOKEN_INVALID
    private var shotToken = NOTIFY_TOKEN_INVALID

    init() {
        notify_register_check(Self.widthName, &widthToken)
        notify_register_check(Self.appliedName, &appliedToken)
        notify_register_check(Self.shotName, &shotToken)
    }

    deinit {
        for token in [widthToken, appliedToken, shotToken] where token != NOTIFY_TOKEN_INVALID {
            notify_cancel(token)
        }
    }

    /// `nil` — the whole window.
    func set(_ width: CGFloat?) {
        notify_set_state(widthToken, UInt64((width ?? 0).rounded()))
        notify_post(Self.widthName)
    }

    /// The width the app root reports, 0 before the first layout.
    var applied: CGFloat {
        var state: UInt64 = 0
        notify_get_state(appliedToken, &state)
        return CGFloat(state)
    }

    /// The last marker the host answered.
    var shotAnswer: UInt64 {
        var state: UInt64 = 0
        notify_get_state(shotToken, &state)
        return state
    }
}
