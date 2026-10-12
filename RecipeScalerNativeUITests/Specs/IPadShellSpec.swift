import UIKit
import XCTest

/// Spec coverage: specs/081-ipad-adaptation/spec.md, US1 (the iPad shell), T022.
///
/// iPad only, iPadOS 26.2+ (`IPadAdaptiveTabView`), portrait. In portrait the sidebar
/// is an overlay over the top tab bar; the tests open it with the system toggle.
///
/// What the accessibility tree looks like (checked on iPadOS 26.3):
///   - top bar items are buttons `tab_*` / `tab-assistant` without badge counts
///     (`isSelected` marks the section; axe reports them as radio buttons);
///   - sidebar rows are plain elements `tab_*`, `ipad-sidebar-collection-<id>`, their
///     labels end with the badge («Покупки, 1»);
///   - the sidebar toggle is `ToggleSideBar` in the top bar, `ToggleSidebar` in the sidebar;
///   - the «Новая коллекция» section action and the alert field carry no identifier.
final class IPadShellSpec: BaseTestCase {
    private var seededDisplayName: String?
    private var seededShoppingItem: String?

    @MainActor
    override func setUp() async throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "iPad shell (spec 081) — iPad only"
        )
        try XCTSkipUnless(
            ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 26, minorVersion: 2, patchVersion: 0)
            ),
            "The sidebar shell needs iPadOS 26.2+; older systems keep the phone shell"
        )
        XCUIDevice.shared.orientation = .portrait
        try await super.setUp()
    }

    override func extraLaunchArguments() -> [String] {
        if name.contains("testCompactHasNoMoreTab") {
            // Window ½ stand-in (IPadLayoutMetrics.regularMinWidth is 680).
            return ["-OpenTab=recipes", "-DebugWindowWidth=400"]
        }
        if name.contains("testTopBarHasNoBadges") {
            return ["-OpenTab=shopping", "-IPadSidebarHidden=1"]
        }
        if name.contains("testTopBar") || name.contains("testProfileHasNoShakeRow") {
            return ["-OpenTab=recipes", "-IPadSidebarHidden=1"]
        }
        if name.contains("Collection") || name.contains("testFooterOpensProfileSheet") {
            // Recipes shows its own «Новая коллекция» tile; start elsewhere.
            return ["-OpenTab=shopping"]
        }
        return ["-OpenTab=recipes"]
    }

    override func prepareBeforeLaunch() async throws {
        if name.contains("testTopBarHasNoBadges") {
            let item = TestData.shoppingItemLabel("E2E iPad")
            try await seedOrSkip("POST /api/shopping-list/items") {
                try await seedClient.addShoppingItems([item])
            }
            seededShoppingItem = item
        }
        if name.contains("testFooterOpensProfileSheet") {
            let displayName = "E2E iPad \(UUID().uuidString.prefix(6))"
            try await seedOrSkip("PATCH /api/users/name") {
                try await seedClient.setDisplayName(displayName)
            }
            seededDisplayName = displayName
        }
    }

    // MARK: - Sidebar

    func testSidebarContents() {
        showSidebar()
        for id in [UIA.tabDiscover, UIA.tabRecipes, UIA.tabShopping] {
            XCTAssertTrue(element(id).waitForExistence(timeout: Wait.element), "\(id) row missing from the sidebar")
        }
        XCTAssertTrue(element(UIA.ipadSidebarCollections).exists, "«Коллекции» section missing")
        XCTAssertTrue(waitUntil { self.newCollectionAction() != nil }, "«Новая коллекция» action missing")
        XCTAssertTrue(footer.isHittable, "Profile footer missing at the bottom of the sidebar")
    }

    func testFooterPrivateShowsAccountId() {
        showSidebar()
        let userId = e2eUser.userId
        let accountId = "\(userId.prefix(3))·\(userId.suffix(3))"
        XCTAssertTrue(
            waitUntil(timeout: Wait.firstPaint) { self.footer.label.contains(accountId) },
            "A private profile footer shows the account number \(accountId), got «\(footer.label)»"
        )
    }

    func testCollectionTapOpensRecipes() {
        showSidebar()
        let (row, name) = createCollectionFromSidebar()
        showSidebar()
        row.tap()
        XCTAssertTrue(
            app.navigationBars[name].waitForExistence(timeout: Wait.element),
            "Collection «\(name)» did not open in Recipes"
        )
        showSidebar()
        XCTAssertTrue(waitUntil { row.isSelected }, "The collection row is not selected in the sidebar")
    }

    func testNewCollectionFromSidebar() {
        showSidebar()
        let (row, name) = createCollectionFromSidebar()
        XCTAssertTrue(row.label.hasPrefix(name), "New collection row shows «\(row.label)», expected «\(name)»")
    }

    func testCollectionInTopBarShowsRecipesTab() {
        showSidebar()
        let (row, name) = createCollectionFromSidebar()
        showSidebar()
        row.tap()
        // A tap closes the overlay sidebar: the top bar is back.
        XCTAssertTrue(waitUntil { !self.footer.exists }, "Overlay sidebar stayed open after a collection tap")
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: Wait.element), "Collection «\(name)» did not open")
        let recipes = topBarTab(UIA.tabRecipes)
        XCTAssertTrue(waitUntil { recipes.isSelected }, "«Рецепты» is not selected in the top bar")
        let collectionInBar = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", UIA.ipadSidebarCollectionPrefix))
            .firstMatch
        XCTAssertFalse(collectionInBar.exists, "A collection got into the top bar")
    }

    func testSidebarHasNoProfileTab() {
        showSidebar()
        XCTAssertTrue(element(UIA.tabRecipes).exists, "Sidebar rows missing")
        XCTAssertTrue(
            waitUntil { !self.element(UIA.tabProfile).exists && !self.element(UIA.assistantTab).exists },
            "«Профиль» / «Ассистент» are rows of the sidebar"
        )
    }

    // MARK: - Profile sheet

    func testFooterOpensProfileSheet() throws {
        let displayName = try XCTUnwrap(seededDisplayName)
        XCTAssertTrue(element(UIA.shoppingList).waitForExistence(timeout: Wait.firstPaint), "Shopping did not open")
        showSidebar()
        footer.tap()
        XCTAssertTrue(profileDoneButton.waitForExistence(timeout: Wait.element), "Profile sheet did not open")
        accountPage.awaitReady()

        let publicSwitch = app.switches
            .matching(NSPredicate(format: "label IN %@", ["Публичный профиль", "Public profile"]))
            .firstMatch
        scrollAccount(until: publicSwitch)
        XCTAssertTrue(publicSwitch.waitForExistence(timeout: Wait.firstPaint), "«Публичный профиль» switch missing")
        publicSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(
            waitUntil(timeout: Wait.firstPaint) { (publicSwitch.value as? String) == "1" && publicSwitch.isEnabled },
            "Public profile did not turn on"
        )

        profileDoneButton.tap()
        XCTAssertTrue(waitUntil { !self.accountPage.root.exists }, "«Готово» did not close the sheet")
        XCTAssertTrue(element(UIA.shoppingList).exists, "The section under the sheet changed")
        XCTAssertTrue(waitUntil { self.topBarTab(UIA.tabShopping).isSelected }, "«Покупки» is no longer selected")

        showSidebar()
        XCTAssertTrue(
            waitUntil(timeout: Wait.firstPaint) { self.footer.label.contains(displayName) },
            "Footer did not show the public name «\(displayName)», got «\(footer.label)»"
        )
    }

    func testTopBarProfileOpensSheet() {
        recipeListPage.awaitReady()
        let profile = topBarTab(UIA.tabProfile)
        XCTAssertTrue(profile.waitForExistence(timeout: Wait.element), "«Профиль» missing from the top bar")
        profile.tap()
        XCTAssertTrue(profileDoneButton.waitForExistence(timeout: Wait.element), "Profile sheet did not open")
        accountPage.awaitReady()

        profileDoneButton.tap()
        XCTAssertTrue(waitUntil { !self.accountPage.root.exists }, "«Готово» did not close the sheet")
        XCTAssertTrue(waitUntil { self.topBarTab(UIA.tabRecipes).isSelected }, "The selection moved off «Рецепты»")
        XCTAssertFalse(topBarTab(UIA.tabProfile).isSelected, "«Профиль» became the selected tab")
        recipeListPage.awaitReady()
    }

    func testProfileHasNoShakeRow() {
        recipeListPage.awaitReady()
        let profile = topBarTab(UIA.tabProfile)
        XCTAssertTrue(profile.waitForExistence(timeout: Wait.element), "«Профиль» missing from the top bar")
        profile.tap()
        accountPage.awaitReady()
        // The shake row sits right above the timer notifications row: once that row
        // is loaded, a shake row would be too.
        let timerToggle = element(UIA.accountTimerNotificationsToggle)
        scrollAccount(until: timerToggle)
        XCTAssertTrue(timerToggle.exists, "Timer notifications row not reached")
        XCTAssertFalse(element(UIA.accountShakeOpenAssistantToggle).exists, "The iPad profile shows the shake row")
    }

    // MARK: - Top bar and compact

    func testTopBarHasNoBadges() throws {
        let item = try XCTUnwrap(seededShoppingItem)
        XCTAssertTrue(element(UIA.shoppingList).waitForExistence(timeout: Wait.firstPaint), "Shopping did not open")
        XCTAssertTrue(app.staticTexts[item].waitForExistence(timeout: Wait.firstPaint), "Seeded item did not sync")

        let shopping = topBarTab(UIA.tabShopping)
        XCTAssertTrue(shopping.waitForExistence(timeout: Wait.element), "«Покупки» missing from the top bar")
        XCTAssertFalse(hasDigits(shopping.label), "Top bar «Покупки» shows a badge: «\(shopping.label)»")
        XCTAssertFalse(hasDigits(topBarTab(UIA.tabRecipes).label), "Top bar «Рецепты» shows a badge")

        showSidebar()
        XCTAssertTrue(
            waitUntil { self.hasDigits(self.element(UIA.tabShopping).label) },
            "The sidebar «Покупки» row lost its badge: «\(element(UIA.tabShopping).label)»"
        )
    }

    func testCompactHasNoMoreTab() {
        for id in [UIA.tabDiscover, UIA.tabRecipes, UIA.tabShopping, UIA.tabProfile, UIA.assistantTab] {
            XCTAssertTrue(element(id).waitForExistence(timeout: Wait.firstPaint), "\(id) missing from the bottom bar")
        }
        let more = app.buttons.matching(NSPredicate(format: "label IN %@", ["Ещё", "More"])).firstMatch
        XCTAssertFalse(more.exists, "Compact bar has a «Ещё» tab")
        XCTAssertFalse(footer.exists, "Compact window shows the sidebar footer")

        element(UIA.tabProfile).tap()
        accountPage.awaitReady()
        XCTAssertFalse(element(UIA.ipadProfileSheetDoneButton).exists, "Compact profile opened as a sheet, expected a tab page")
    }

    // MARK: - Helpers

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func topBarTab(_ id: String) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    private var footer: XCUIElement { element(UIA.ipadSidebarFooter) }

    private var sidebarToggle: XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier IN %@", ["ToggleSideBar", "ToggleSidebar"]))
            .firstMatch
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

    private func hasDigits(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .decimalDigits) != nil
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval = Wait.element, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func showSidebar(file: StaticString = #filePath, line: UInt = #line) {
        if footer.exists, footer.isHittable { return }
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: Wait.firstPaint), "Sidebar toggle missing", file: file, line: line)
        sidebarToggle.tap()
        XCTAssertTrue(
            waitUntil { self.footer.exists && self.footer.isHittable },
            "Sidebar did not show",
            file: file,
            line: line
        )
    }

    private func scrollAccount(until target: XCUIElement) {
        for _ in 0..<8 where !target.exists {
            accountPage.root.swipeUp()
        }
    }

    /// The sidebar «Новая коллекция» action: matched by label inside the sidebar column.
    private func newCollectionAction() -> XCUIElement? {
        let candidates = app.descendants(matching: .any).matching(NSPredicate(
            format: "label IN %@ AND identifier != %@",
            ["Новая коллекция", "New collection"],
            UIA.collectionsNewRow
        ))
        let sidebarMaxX = footer.frame.maxX
        for index in 0..<candidates.count {
            let candidate = candidates.element(boundBy: index)
            if candidate.exists, candidate.isHittable, candidate.frame.maxX <= sidebarMaxX + 1 {
                return candidate
            }
        }
        return nil
    }

    /// Creates a collection through the sidebar action and returns its sidebar row.
    private func createCollectionFromSidebar() -> (row: XCUIElement, name: String) {
        var action: XCUIElement?
        // The action follows the last collection: a long list pushes it off screen.
        for _ in 0..<4 {
            if waitUntil(timeout: 2, { action = self.newCollectionAction(); return action != nil }) { break }
            element(UIA.tabShopping).swipeUp()
        }
        guard let action else {
            XCTFail("«Новая коллекция» missing from the sidebar")
            return (element(UIA.ipadSidebarCollectionPrefix), "")
        }
        action.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: Wait.element), "New collection alert did not open")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Wait.element), "Collection name field missing")
        let create = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Создать", "Create"])).firstMatch
        field.tap()
        field.typeText("   ")
        XCTAssertFalse(create.isEnabled, "«Создать» is enabled for a blank name")

        let name = TestData.collectionName("E2E iPad")
        field.typeText(name)
        XCTAssertTrue(create.isEnabled, "«Создать» stays disabled for «\(name)»")
        create.tap()

        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
            UIA.ipadSidebarCollectionPrefix,
            name
        )).firstMatch
        showSidebar()
        XCTAssertTrue(row.waitForExistence(timeout: Wait.firstPaint), "Collection «\(name)» row missing from the sidebar")
        return (row, name)
    }
}
