import UIKit
import XCTest

/// Spec coverage: specs/081-ipad-adaptation/spec.md, US3 (the assistant panel), T035.
///
/// iPad only, iPadOS 26.2+, landscape with the sidebar hidden: the pinned «Ассистент» tab
/// of the top bar opens and closes a 340 pt panel beside the tab view (FR-019, FR-021);
/// on «Рецептах» the open panel hides the list column, the recipe keeps two columns
/// (FR-022, layout.md `#assistant/chat`). One chat for the panel and the sheet (plan.md Р7).
/// `testToolbarButtonTogglesPanel` starts with the sidebar, so the entry is ✦ in the toolbar;
/// beside the panel iPadOS folds the sidebar into the top bar (see the test).
///
/// Every test gets a fresh user with one recipe seeded over REST and the DEBUG assistant
/// fixture (`-ScreenshotAssistantFixture=1`: a canned chat, no backend thread, no LLM), so
/// «the same chat» is the canned question on screen.
///
/// A size class change needs a real window resize, which the simulator cannot script;
/// `-DebugCompactInPortrait=1` makes the portrait window a compact ½ one, so a rotation is a
/// runtime regular ↔ compact switch (`testSizeClassSwitchKeepsChat`).
///
/// In landscape the XCTest screenshot on the iPadOS 26 simulator is a cropped portrait
/// buffer; take review shots with `simctl io screenshot` instead.
final class IPadAssistantSpec: BaseTestCase {
    private var recipe: SeedClient.CreatedRecipe!

    /// The canned question of the fixture chat, Russian or English UI.
    private static let fixtureQuestion = ["Соус свернулся", "My sauce split"]
    private static let draft = "Draft 081 panel"

    @MainActor
    override func setUp() async throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "iPad assistant panel (spec 081) — iPad only"
        )
        try XCTSkipUnless(
            ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 26, minorVersion: 2, patchVersion: 0)
            ),
            "The panel lives in the iPadOS 26.2+ shell; older systems keep the phone shell"
        )
        try await super.setUp()
        rotate(to: .landscapeLeft)
    }

    @MainActor
    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
        try await super.tearDown()
    }

    /// ✦ is in the section toolbars only while the sidebar is shown.
    private var keepsSidebar: Bool { name.contains("testToolbarButtonTogglesPanel") }

    override func extraLaunchArguments() -> [String] {
        var args = [
            keepsSidebar ? "-OpenTab=shopping" : "-OpenTab=recipes",
            keepsSidebar ? "-IPadSidebarShown=1" : "-IPadSidebarHidden=1",
            "-ScreenshotAssistantFixture=1",
        ]
        if name.contains("testSizeClassSwitchKeepsChat") {
            args.append("-DebugCompactInPortrait=1")
        }
        return args
    }

    override func prepareBeforeLaunch() async throws {
        recipe = try await seedOrSkip("POST /api/recipes") {
            try await self.seedClient.createRecipe(name: TestData.recipeName("E2E Panel"))
        }
    }

    // MARK: - Panel

    /// `#assistant/chat`: the pinned tab opens a 340 pt panel at the trailing edge, the list
    /// column hides, the recipe keeps two columns and the selected tab. × and the tab close it.
    func testInspectorOpensFromRecipe() {
        awaitRecipe()
        XCTAssertTrue(waitUntil { self.listOnScreen }, "No list column before the panel opens")

        openPanelFromTopBar()
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(inspector.frame.width, 340, accuracy: 2, "The panel is \(inspector.frame.width) pt wide")
        XCTAssertEqual(inspector.frame.maxX, window.maxX, accuracy: 1, "The panel is not at the trailing edge")
        XCTAssertTrue(waitUntil { !self.listOnScreen }, "The list column stays beside the recipe and the panel")
        XCTAssertEqual(rowCount, 0, "Rows of the hidden list are still in the tree")
        awaitTwoColumns()
        XCTAssertLessThanOrEqual(rightColumn.frame.maxX, inspector.frame.minX + 1, "The recipe runs under the panel")
        XCTAssertFalse(element(UIA.ipadRecipeExpandButton).exists, "«Развернуть» beside the panel")
        XCTAssertTrue(topBarTab(UIA.tabRecipes).isSelected, "The selection moved off «Рецепты»")
        assertPanelChrome()
        assertClearOfTabBar(app.buttons.matching(identifier: UIA.recipeDetailMenu).firstMatch, "recipe «…»")
        XCTAssertTrue(fixtureQuestion.waitForExistence(timeout: Wait.element), "The panel shows no chat")
        capture("assistant-panel-recipes")

        closeButton.tap()
        XCTAssertTrue(waitUntil { !self.inspector.exists }, "× did not close the panel")
        XCTAssertTrue(waitUntil { self.listOnScreen }, "Closing the panel did not bring the list back")
        XCTAssertTrue(recipeListPage.recipeRow(id: recipe.id).waitForExistence(timeout: Wait.element), "No rows after the panel closed")

        // The pinned tab toggles the panel and never becomes the selected tab.
        openPanelFromTopBar()
        topBarTab(UIA.assistantTab).tap()
        XCTAssertTrue(waitUntil { !self.inspector.exists }, "The «Ассистент» tab did not close the panel")
        XCTAssertTrue(topBarTab(UIA.tabRecipes).isSelected, "The selection moved off «Рецепты»")
        XCTAssertFalse(topBarTab(UIA.assistantTab).isSelected, "«Ассистент» became the selected tab")
    }

    /// The panel stands beside every section and keeps its chat; the toolbars of the
    /// sections stay clear of the top bar.
    func testTabSwitchKeepsInspector() {
        awaitRecipe()
        openPanelFromTopBar()
        XCTAssertTrue(fixtureQuestion.waitForExistence(timeout: Wait.element), "The panel shows no chat")

        topBarTab(UIA.tabShopping).tap()
        shoppingListPage.awaitReady()
        XCTAssertTrue(inspector.exists, "The panel closed on «Покупки»")
        XCTAssertTrue(fixtureQuestion.exists, "The chat changed on «Покупки»")
        XCTAssertTrue(topBarTab(UIA.tabShopping).isSelected, "«Покупки» is not selected")
        let share = app.buttons.matching(identifier: UIA.shoppingShareButton).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: Wait.element), "No «Поделиться» on «Покупки»")
        assertClearOfTabBar(share, "shopping «Поделиться»")
        XCTAssertLessThanOrEqual(share.frame.maxX, inspector.frame.minX + 1, "«Поделиться» sits under the panel")
        capture("assistant-panel-shopping")

        topBarTab(UIA.tabDiscover).tap()
        XCTAssertTrue(waitUntil { self.topBarTab(UIA.tabDiscover).isSelected }, "«Подборки» is not selected")
        XCTAssertTrue(inspector.exists, "The panel closed on «Подборки»")

        topBarTab(UIA.tabRecipes).tap()
        awaitTwoColumns()
        XCTAssertTrue(inspector.exists, "The panel closed on the way back to «Рецепты»")
        XCTAssertTrue(fixtureQuestion.exists, "The chat changed after the tab switches")
        XCTAssertFalse(listOnScreen, "The list came back beside the open panel")
        assertPanelChrome()
    }

    /// The typed draft survives tab switches and a close / reopen of the panel (plan.md Р7).
    func testTabSwitchKeepsDraft() {
        awaitRecipe()
        openPanelFromTopBar()
        typeDraft()

        topBarTab(UIA.tabShopping).tap()
        shoppingListPage.awaitReady()
        topBarTab(UIA.tabRecipes).tap()
        awaitTwoColumns()
        XCTAssertTrue(waitUntil { self.draftShown }, "The draft is gone after a tab switch: «\(inputValue)»")

        closeButton.tap()
        XCTAssertTrue(waitUntil { !self.inspector.exists }, "× did not close the panel")
        openPanelFromTopBar()
        XCTAssertTrue(waitUntil { self.draftShown }, "The draft is gone after close and reopen: «\(inputValue)»")
    }

    /// Panel → sheet → panel on a runtime size class change keeps the chat and the draft.
    func testSizeClassSwitchKeepsChat() {
        awaitRecipe()
        openPanelFromTopBar()
        XCTAssertTrue(fixtureQuestion.waitForExistence(timeout: Wait.element), "The panel shows no chat")
        typeDraft()
        dismissKeyboard()

        // Portrait is a compact window here: the phone sheet with the same chat.
        rotate(to: .portrait)
        XCTAssertTrue(waitUntil(timeout: Wait.firstPaint) { !self.inspector.exists }, "The panel stayed in a compact window")
        XCTAssertTrue(
            waitUntil(timeout: Wait.firstPaint) { self.assistantPage.sheet.exists && !self.closeButton.exists },
            "No assistant sheet in a compact window"
        )
        XCTAssertTrue(fixtureQuestion.exists, "The sheet lost the chat")
        XCTAssertTrue(waitUntil { self.draftShown }, "The sheet lost the draft: «\(inputValue)»")
        capture("assistant-compact-sheet")

        rotate(to: .landscapeLeft)
        XCTAssertTrue(inspector.waitForExistence(timeout: Wait.firstPaint), "The panel did not come back in a regular window")
        // The sheet and the panel would show the chat twice.
        XCTAssertTrue(waitUntil { self.fixtureQuestions.count == 1 }, "The sheet stayed over the panel")
        XCTAssertTrue(fixtureQuestion.exists, "The panel lost the chat after the sheet")
        XCTAssertTrue(waitUntil { self.draftShown }, "The panel lost the draft after the sheet: «\(inputValue)»")
        XCTAssertEqual(inspector.frame.width, 340, accuracy: 2, "The panel came back \(inspector.frame.width) pt wide")
    }

    /// `#assistant/history`: the clock opens the chat list as a popover over the chat, not a
    /// sheet over the window; a tap outside closes it and the panel stays.
    func testHistoryPopover() {
        awaitRecipe()
        openPanelFromTopBar()
        historyButton.tap()

        let list = element(UIA.assistantThreadPanel)
        XCTAssertTrue(list.waitForExistence(timeout: Wait.element), "The clock did not open the chat list")
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(list.frame.width, window.width / 2, "The chat list is \(list.frame.width) pt wide: a sheet, not a popover")
        XCTAssertGreaterThan(list.frame.maxX, inspector.frame.minX, "The popover is not over the panel")
        XCTAssertTrue(inspector.exists, "The panel closed under the popover")
        capture("assistant-history-popover")

        // A tap on the recipe, outside the popover.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.6)).tap()
        XCTAssertTrue(waitUntil { !list.exists }, "A tap outside did not close the popover")
        XCTAssertTrue(inspector.exists, "The panel closed with the popover")
        XCTAssertTrue(fixtureQuestion.exists, "The chat changed after the popover")
    }

    /// FR-021: with the sidebar shown, ✦ in the «Покупки» toolbar opens the panel and the
    /// section stays. Beside the panel the tab view narrows (11″ landscape: 1210 → 869 pt)
    /// and iPadOS folds the sidebar into the top bar, as in portrait 834 (layout.md
    /// §Матрица, the edge rows): the pinned «Ассистент» tab is then the entry and closes
    /// the panel, and the sidebar comes back with ✦.
    func testToolbarButtonTogglesPanel() {
        shoppingListPage.awaitReady()
        let star = app.buttons.matching(identifier: UIA.ipadAssistantToolbarButton).firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: Wait.element), "No ✦ in the «Покупки» toolbar")
        XCTAssertTrue(waitUntil { star.isHittable }, "✦ is not hittable")
        capture("assistant-shopping-sidebar-star")

        star.tap()
        XCTAssertTrue(inspector.waitForExistence(timeout: Wait.element), "✦ did not open the panel")
        XCTAssertEqual(inspector.frame.width, 340, accuracy: 2, "The panel is \(inspector.frame.width) pt wide")
        XCTAssertTrue(element(UIA.shoppingList).exists, "«Покупки» went away behind the panel")
        let tab = topBarTab(UIA.assistantTab)
        XCTAssertTrue(
            waitUntil { tab.exists && tab.isHittable && !(star.exists && star.isHittable) },
            "The sidebar did not fold into the top bar beside the panel: no pinned «Ассистент» tab"
        )
        XCTAssertLessThanOrEqual(tab.frame.maxX, inspector.frame.minX + 1, "The «Ассистент» tab sits under the panel")
        assertPanelChrome()
        capture("assistant-panel-shopping-from-star")

        tab.tap()
        XCTAssertTrue(waitUntil { !self.inspector.exists }, "The «Ассистент» tab did not close the panel")
        XCTAssertTrue(element(UIA.shoppingList).exists, "«Покупки» went away with the panel")
        XCTAssertTrue(waitUntil { star.exists && star.isHittable }, "The sidebar and ✦ did not come back after the panel closed")
    }

    // MARK: - Helpers

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func topBarTab(_ id: String) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    /// The panel, by its bar: the one with ×. The panel has no id of its own
    /// (`UIA.ipadAssistantInspectorCloseButton`).
    private var inspector: XCUIElement {
        app.navigationBars.containing(.button, identifier: UIA.ipadAssistantInspectorCloseButton).firstMatch
    }
    private var closeButton: XCUIElement { app.buttons.matching(identifier: UIA.ipadAssistantInspectorCloseButton).firstMatch }
    private var historyButton: XCUIElement { app.buttons.matching(identifier: UIA.assistantHistoryButton).firstMatch }
    private var newChatButton: XCUIElement { app.buttons.matching(identifier: UIA.assistantNewThreadButton).firstMatch }
    private var listColumn: XCUIElement { element(UIA.ipadRecipeListColumn) }
    private var leftColumn: XCUIElement { app.scrollViews.matching(identifier: UIA.ipadRecipeDetailLeftColumn).firstMatch }
    private var rightColumn: XCUIElement { app.scrollViews.matching(identifier: UIA.ipadRecipeDetailRightColumn).firstMatch }

    private var fixtureQuestions: XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@",
            Self.fixtureQuestion[0],
            Self.fixtureQuestion[1]
        ))
    }

    private var fixtureQuestion: XCUIElement { fixtureQuestions.firstMatch }

    /// The list column on screen. Hidden, it waits off the leading edge.
    private var listOnScreen: Bool {
        listColumn.exists && listColumn.frame.maxX > 1
    }

    private var rowCount: Int {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", UIA.recipeRowPrefix)).count
    }

    /// The composer field. On iOS 26 the chat's `assistant_sheet` id replaces the ids of
    /// the chat's top-level elements, the field's own `assistant_message_input` included.
    private var messageInput: XCUIElement {
        let candidates = [
            app.textViews.matching(identifier: UIA.assistantMessageInput).firstMatch,
            app.textFields.matching(identifier: UIA.assistantMessageInput).firstMatch,
            app.textViews.matching(identifier: UIA.assistantSheet).firstMatch,
            app.textFields.matching(identifier: UIA.assistantSheet).firstMatch,
        ]
        return candidates.first(where: \.exists) ?? candidates[3]
    }

    private var inputValue: String {
        (messageInput.value as? String) ?? ""
    }

    private var draftShown: Bool {
        messageInput.exists && inputValue.contains(Self.draft)
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
        XCTAssertTrue(leftColumn.waitForExistence(timeout: Wait.firstPaint), "No left recipe column", file: file, line: line)
        XCTAssertTrue(rightColumn.exists, "No steps column", file: file, line: line)
    }

    private func openPanelFromTopBar(file: StaticString = #filePath, line: UInt = #line) {
        let tab = topBarTab(UIA.assistantTab)
        XCTAssertTrue(tab.waitForExistence(timeout: Wait.element), "«Ассистент» missing from the top bar", file: file, line: line)
        tab.tap()
        XCTAssertTrue(inspector.waitForExistence(timeout: Wait.element), "The «Ассистент» tab did not open the panel", file: file, line: line)
        XCTAssertFalse(waitUntil(timeout: 2) { self.chatOutsidePanel }, "A sheet opened over the panel", file: file, line: line)
    }

    /// Chat content left of the window's middle: a sheet (form or page), never the 340 pt
    /// panel at the trailing edge. `assistantPage.sheet` alone also matches the panel's chat
    /// (the same `assistant_sheet` id).
    private var chatOutsidePanel: Bool {
        let window = app.windows.firstMatch.frame
        return app.descendants(matching: .any).matching(identifier: UIA.assistantSheet)
            .allElementsBoundByIndex
            .contains { $0.exists && !$0.frame.isEmpty && $0.frame.minX < window.midX }
    }

    /// History, «Новый чат» and × sit in the panel's own bar, all reachable.
    private func assertPanelChrome(file: StaticString = #filePath, line: UInt = #line) {
        for (button, name) in [(historyButton, "history"), (newChatButton, "new chat"), (closeButton, "×")] {
            XCTAssertTrue(button.waitForExistence(timeout: Wait.element), "No \(name) button in the panel", file: file, line: line)
            XCTAssertTrue(waitUntil { button.isHittable }, "The \(name) button is not hittable", file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.frame.minX, inspector.frame.minX - 1, "The \(name) button is outside the panel", file: file, line: line)
        }
    }

    /// A section toolbar item is hittable and does not slide under the floating top tab bar.
    private func assertClearOfTabBar(_ item: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.waitForExistence(timeout: Wait.element), "No \(name)", file: file, line: line)
        XCTAssertTrue(waitUntil { item.isHittable }, "\(name) is not hittable", file: file, line: line)
        for id in [UIA.tabDiscover, UIA.tabRecipes, UIA.tabShopping, UIA.assistantTab] {
            let tab = topBarTab(id)
            guard tab.exists else { continue }
            XCTAssertFalse(item.frame.intersects(tab.frame), "\(name) sits under the top bar tab \(id)", file: file, line: line)
        }
    }

    private func typeDraft(file: StaticString = #filePath, line: UInt = #line) {
        let input = messageInput
        XCTAssertTrue(input.waitForExistence(timeout: Wait.element), "No composer in the panel", file: file, line: line)
        input.tap()
        input.typeText(Self.draft)
        XCTAssertTrue(waitUntil { self.draftShown }, "The draft did not land in the composer: «\(inputValue)»", file: file, line: line)
    }

    /// The software keyboard would cover the sheet after the rotation; the draft stays typed.
    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        _ = waitUntil { !self.app.keyboards.firstMatch.exists }
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
        if wantsLandscape, !keepsSidebar { hideSidebarIfShown() }
    }

    /// The system brings the landscape sidebar back after a rotation even when the app
    /// launched with it hidden. Its own toggle (`ToggleSidebar`) is the sign it is shown.
    private func hideSidebarIfShown() {
        let toggle = app.buttons.matching(identifier: "ToggleSidebar").firstMatch
        guard toggle.waitForExistence(timeout: 3), toggle.isHittable else { return }
        toggle.tap()
        XCTAssertTrue(waitUntil { !(toggle.exists && toggle.isHittable) }, "Sidebar did not hide")
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
