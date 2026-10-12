//
//  IPadLayoutPolicyTests.swift
//
//  Spec 081 (T007) — iPad layout policy against layout.md §Токены and §Матрица приёмки.
//

import CoreGraphics
import XCTest
@testable import RecipeScalerNative

final class IPadLayoutPolicyTests: XCTestCase {

    /// `height` defaults to a landscape window (11-inch, 834 pt tall): a third for the list.
    private func layout(
        _ contentWidth: CGFloat,
        height: CGFloat = 834,
        recipeExpanded: Bool = false,
        isEditing: Bool = false,
        assistantBesideRecipe: Bool = false
    ) -> IPadLayout {
        IPadLayoutPolicy.resolve(
            contentWidth: contentWidth,
            contentHeight: height,
            recipeExpanded: recipeExpanded,
            isEditing: isEditing,
            assistantBesideRecipe: assistantBesideRecipe
        )
    }

    // MARK: - List column proportions (Notes-style)

    func testListTakesHalfInPortraitAndAThirdInLandscape() {
        // iPad Pro 11" M4: portrait 834 × 1210, landscape 1210 × 834.
        XCTAssertEqual(IPadLayoutPolicy.listColumnWidth(contentWidth: 834, contentHeight: 1210), 417)
        XCTAssertEqual(IPadLayoutPolicy.listColumnWidth(contentWidth: 1210, contentHeight: 834), 403)
        // 13": portrait 1032 × 1376, landscape 1376 × 1032.
        XCTAssertEqual(IPadLayoutPolicy.listColumnWidth(contentWidth: 1032, contentHeight: 1376), 516)
        XCTAssertEqual(IPadLayoutPolicy.listColumnWidth(contentWidth: 1376, contentHeight: 1032), 458)
        // A square is not portrait: portrait means taller than wide.
        XCTAssertEqual(IPadLayoutPolicy.listColumnWidth(contentWidth: 1000, contentHeight: 1000), 333)
    }

    func testListNeverNarrowerThan320() {
        // Landscape with the sidebar beside the content: a third of 930 is 310.
        XCTAssertEqual(IPadLayoutPolicy.listColumnWidth(contentWidth: 930, contentHeight: 834), 320)
        // Portrait 680 (the regular minimum): half is 340.
        XCTAssertEqual(IPadLayoutPolicy.listColumnWidth(contentWidth: 680, contentHeight: 1000), 340)
        XCTAssertEqual(IPadLayoutPolicy.listColumnWidth(contentWidth: 600, contentHeight: 1000), 320)
    }

    func testPortraitSplitsInHalfWithOneColumnRecipe() {
        let portrait = layout(834, height: 1210)
        XCTAssertTrue(portrait.splitFits)
        XCTAssertTrue(portrait.listShown)
        XCTAssertEqual(portrait.listWidth, 417)
        XCTAssertEqual(portrait.detailWidth, 416)
        XCTAssertFalse(portrait.twoColumns)
        XCTAssertTrue(portrait.showsExpandButton)
    }

    func testLandscapeGivesTheRecipeTwoThirdsAndTwoColumns() {
        let landscape = layout(1210)
        XCTAssertTrue(landscape.listShown)
        XCTAssertEqual(landscape.listWidth, 403)
        XCTAssertEqual(landscape.detailWidth, 806)
        XCTAssertTrue(landscape.twoColumns)
        XCTAssertEqual(landscape.toolbarStyle, .padWide)
    }

    func testSidebarInLandscapeAppliesTheRuleToTheRest() {
        let withSidebar = layout(1210 - IPadLayoutMetrics.sidebarWidth)
        XCTAssertTrue(withSidebar.listShown)
        XCTAssertEqual(withSidebar.listWidth, 320)
        XCTAssertEqual(withSidebar.detailWidth, 609)
        XCTAssertFalse(withSidebar.twoColumns)
    }

    func testExpandedRecipeTakesTheWholeContent() {
        for (width, height, list): (CGFloat, CGFloat, CGFloat) in [(834, 1210, 417), (1210, 834, 403), (930, 834, 320)] {
            let expanded = layout(width, height: height, recipeExpanded: true)
            XCTAssertTrue(expanded.splitFits, "W=\(width)")
            XCTAssertFalse(expanded.listShown, "W=\(width)")
            XCTAssertEqual(expanded.listWidth, list, "W=\(width): the column waits off screen")
            XCTAssertEqual(expanded.detailWidth, width, "W=\(width)")
            XCTAssertTrue(expanded.twoColumns, "W=\(width)")
            XCTAssertTrue(expanded.showsExpandButton, "W=\(width): «Свернуть» stays")
        }
    }

    // MARK: - Thresholds (value and 1 pt below)

    func testSplitThresholdKeeps320ForTheRecipe() {
        // Landscape: the list is 320 up to 961, so the split needs 320 + 1 + 320.
        let atThreshold = layout(641)
        XCTAssertTrue(atThreshold.splitFits)
        XCTAssertTrue(atThreshold.listShown)
        XCTAssertEqual(atThreshold.detailWidth, 320)

        let below = layout(640)
        XCTAssertFalse(below.splitFits)
        XCTAssertFalse(below.listShown)
        XCTAssertEqual(below.detailWidth, 640)
        XCTAssertFalse(below.showsExpandButton, "the phone stack has nothing to expand")

        // Portrait: half of the content until it is under 641 as well.
        XCTAssertTrue(layout(641, height: 1000).splitFits)
        XCTAssertFalse(layout(640, height: 1000).splitFits)
    }

    func testTwoColumnThresholdAt720() {
        XCTAssertTrue(layout(720, recipeExpanded: true).twoColumns)
        XCTAssertFalse(layout(719, recipeExpanded: true).twoColumns)
        // With the list shown the panel is what counts: 720 + 1 + 360 (a third) → two
        // columns, 1 pt less → one.
        XCTAssertEqual(layout(1081).detailWidth, 720)
        XCTAssertTrue(layout(1081).twoColumns)
        XCTAssertFalse(layout(1080).twoColumns)
    }

    func testWideToolbarThresholdAt600() {
        XCTAssertEqual(layout(600, recipeExpanded: true).toolbarStyle, .padWide)
        XCTAssertEqual(layout(599, recipeExpanded: true).toolbarStyle, .padNarrow)
        // A third for the list: 600 + 1 + 320 → wide, 1 pt less → narrow.
        XCTAssertEqual(layout(921).toolbarStyle, .padWide)
        XCTAssertEqual(layout(920).toolbarStyle, .padNarrow)
    }

    func testVkusvillLabelThresholdAt640() {
        XCTAssertFalse(layout(640).shopVkusvillIconOnly)
        XCTAssertTrue(layout(639).shopVkusvillIconOnly)
    }

    func testEditingHidesTheList() {
        // layout.md §Матрица приёмки: edit mode hides the list, the panel takes the content.
        for width: CGFloat in [1210, 776, 834] {
            let editing = layout(width, isEditing: true)
            XCTAssertFalse(editing.listShown, "W=\(width)")
            XCTAssertEqual(editing.detailWidth, width, "W=\(width)")
            XCTAssertTrue(editing.twoColumns, "W=\(width)")
            XCTAssertFalse(editing.showsExpandButton, "W=\(width)")
        }
    }

    // MARK: - Assistant panel beside a recipe (T034, FR-022)

    /// The measured content already excludes the panel and its divider (340 + 1).
    private func withPanel(_ window: CGFloat, sidebar: CGFloat = 0) -> CGFloat {
        window - sidebar - IPadLayoutMetrics.inspectorWidth - IPadLayoutMetrics.columnDividerWidth
    }

    func testAssistantPanelHidesTheListAtAnyWidth() {
        // iPad Pro 11": landscape top bar, landscape with the sidebar, portrait, 13" landscape.
        let cases: [(content: CGFloat, height: CGFloat, twoColumns: Bool)] = [
            (withPanel(1210), 834, true),
            (withPanel(1210, sidebar: IPadLayoutMetrics.sidebarWidth), 834, false),
            (withPanel(834), 1210, false),
            (withPanel(1376), 1032, true),
        ]
        for (content, height, twoColumns) in cases {
            let resolved = layout(content, height: height, assistantBesideRecipe: true)
            XCTAssertTrue(resolved.splitFits, "W=\(content): the split stays, the recipe view is not swapped")
            XCTAssertFalse(resolved.listShown, "W=\(content)")
            XCTAssertEqual(resolved.detailWidth, content, "W=\(content): the recipe takes the content")
            XCTAssertEqual(resolved.twoColumns, twoColumns, "W=\(content)")
            XCTAssertFalse(resolved.showsExpandButton, "W=\(content): no «Развернуть» beside the panel")
        }
        // Landscape without the sidebar: 869 → the recipe in two columns (layout.md `#assistant/chat`).
        XCTAssertEqual(withPanel(1210), 869)
    }

    func testAssistantPanelKeepsThePhoneStackWhereTheSplitNeverFit() {
        // Landscape ⅔ with the sidebar: 496 has no room for the list even without the panel.
        let content = withPanel(776, sidebar: IPadLayoutMetrics.sidebarWidth)
        let resolved = layout(content, assistantBesideRecipe: true)
        XCTAssertFalse(resolved.splitFits)
        XCTAssertFalse(resolved.listShown)
        XCTAssertEqual(resolved.detailWidth, content)
    }

    func testClosingTheAssistantPanelBringsTheListBack() {
        let open = layout(withPanel(1210), assistantBesideRecipe: true)
        let closed = layout(1210)
        XCTAssertFalse(open.listShown)
        XCTAssertTrue(closed.listShown)
        XCTAssertEqual(closed.listWidth, 403)
        XCTAssertEqual(open.splitFits, closed.splitFits, "the panel never swaps split and stack")
        // An expanded recipe stays expanded under the panel and after it closes.
        let expandedOpen = layout(withPanel(834), height: 1210, recipeExpanded: true, assistantBesideRecipe: true)
        XCTAssertTrue(IPadLayoutPolicy.keepsRecipeExpanded(splitFits: expandedOpen.splitFits, isPadRegular: true))
        XCTAssertTrue(layout(834, height: 1210, recipeExpanded: true).showsExpandButton, "«Свернуть» is back")
    }

    // MARK: - layout.md §Матрица приёмки

    private struct MatrixRow {
        let window: CGFloat
        let height: CGFloat
        let sidebar: Bool
        let inspector: Bool
        let content: CGFloat
        let list: CGFloat?
        let detail: CGFloat
        let twoColumns: Bool
        let toolbar: IPadDetailToolbarStyle
        let vkusvillIconOnly: Bool
    }

    /// `list`: the list column width, `nil` for the phone stack (no room beside the recipe).
    func testPrototypeMatrix() {
        let rows: [MatrixRow] = [
            // iPad Pro 11" M4, landscape, full screen.
            MatrixRow(window: 1210, height: 834, sidebar: true, inspector: false, content: 930, list: 320,
                      detail: 609, twoColumns: false, toolbar: .padWide, vkusvillIconOnly: false),
            MatrixRow(window: 1210, height: 834, sidebar: false, inspector: false, content: 1210, list: 403,
                      detail: 806, twoColumns: true, toolbar: .padWide, vkusvillIconOnly: false),
            MatrixRow(window: 1210, height: 834, sidebar: true, inspector: true, content: 590, list: nil,
                      detail: 590, twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: true),
            MatrixRow(window: 1210, height: 834, sidebar: false, inspector: true, content: 870, list: 320,
                      detail: 549, twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: false),
            // Landscape, 2/3 (taller than wide: portrait proportions).
            MatrixRow(window: 776, height: 834, sidebar: true, inspector: false, content: 496, list: nil,
                      detail: 496, twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: true),
            MatrixRow(window: 776, height: 834, sidebar: false, inspector: false, content: 776, list: 388,
                      detail: 387, twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: false),
            MatrixRow(window: 776, height: 834, sidebar: false, inspector: true, content: 436, list: nil,
                      detail: 436, twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: true),
            // Portrait, full screen. The sidebar floats over the content there (spike S1);
            // the row with it keeps the formula of the matrix.
            MatrixRow(window: 834, height: 1210, sidebar: true, inspector: false, content: 554, list: nil,
                      detail: 554, twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: true),
            MatrixRow(window: 834, height: 1210, sidebar: false, inspector: false, content: 834, list: 417,
                      detail: 416, twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: false),
            MatrixRow(window: 834, height: 1210, sidebar: false, inspector: true, content: 494, list: nil,
                      detail: 494, twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: true),
            // 13-inch, full screen.
            MatrixRow(window: 1376, height: 1032, sidebar: true, inspector: false, content: 1096, list: 365,
                      detail: 730, twoColumns: true, toolbar: .padWide, vkusvillIconOnly: false),
            MatrixRow(window: 1032, height: 1376, sidebar: true, inspector: false, content: 752, list: 376,
                      detail: 375, twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: false),
        ]
        for row in rows {
            let label = "W=\(row.window) sidebar=\(row.sidebar) inspector=\(row.inspector)"
            let content = IPadLayoutPolicy.contentWidth(
                windowWidth: row.window,
                sidebarVisible: row.sidebar,
                inspectorVisible: row.inspector
            )
            XCTAssertEqual(content, row.content, label)
            let resolved = layout(content, height: row.height)
            XCTAssertEqual(resolved.contentWidth, row.content, label)
            XCTAssertEqual(resolved.splitFits, row.list != nil, label)
            XCTAssertEqual(resolved.listShown, row.list != nil, label)
            XCTAssertEqual(resolved.listWidth, row.list ?? 0, label)
            XCTAssertEqual(resolved.detailWidth, row.detail, label)
            XCTAssertEqual(resolved.twoColumns, row.twoColumns, label)
            XCTAssertEqual(resolved.toolbarStyle, row.toolbar, label)
            XCTAssertEqual(resolved.showsExpandButton, row.list != nil, label)
            XCTAssertEqual(resolved.shopVkusvillIconOnly, row.vkusvillIconOnly, label)
            if row.twoColumns {
                XCTAssertEqual(
                    IPadLayoutPolicy.detailLeftWidth(preferred: nil, detailWidth: resolved.detailWidth),
                    IPadLayoutMetrics.detailLeftWidth,
                    "\(label): untouched divider keeps the left column at 400"
                )
            } else {
                XCTAssertNil(IPadLayoutPolicy.detailLeftWidth(preferred: nil, detailWidth: resolved.detailWidth), label)
            }
        }
    }

    /// Sidebar and inspector together in a narrow regular window: only the formula is fixed
    /// here (the phone stack, one column); the on-screen verdict belongs to T049.
    func testMatrixEdgeRowsKeepFormulaValues() {
        for (window, content): (CGFloat, CGFloat) in [(776, 156), (834, 214)] {
            let width = IPadLayoutPolicy.contentWidth(windowWidth: window, sidebarVisible: true, inspectorVisible: true)
            XCTAssertEqual(width, content)
            let resolved = layout(width, height: 834)
            XCTAssertFalse(resolved.splitFits)
            XCTAssertFalse(resolved.listShown)
            XCTAssertEqual(resolved.detailWidth, content)
            XCTAssertFalse(resolved.twoColumns)
            XCTAssertEqual(resolved.toolbarStyle, .padNarrow)
        }
    }

    /// Compact windows (½, ⅓, portrait ⅔) are below the regular minimum width: the system
    /// reports a compact size class there and the phone layout applies (`AppLayoutMode`).
    func testCompactMatrixWidthsAreBelowRegularMinimum() {
        for width: CGFloat in [582, 388, 536, 402, 320] {
            XCTAssertLessThan(width, IPadLayoutMetrics.regularMinWidth, "W=\(width)")
        }
        for width: CGFloat in [1210, 1194, 776, 834, 1376, 1032] {
            XCTAssertGreaterThanOrEqual(width, IPadLayoutMetrics.regularMinWidth, "W=\(width)")
        }
    }

    // MARK: - Recipe column divider (Q5)

    func testLeftColumnClamp() throws {
        XCTAssertEqual(IPadLayoutPolicy.detailLeftWidth(preferred: nil, detailWidth: 873), 400)
        XCTAssertEqual(IPadLayoutPolicy.detailLeftWidth(preferred: 200, detailWidth: 873), 320)
        XCTAssertEqual(IPadLayoutPolicy.detailLeftWidth(preferred: 600, detailWidth: 873), 480)

        // The steps column keeps at least 320: panel − 1 − 320.
        let at720 = IPadLayoutPolicy.detailLeftWidth(preferred: nil, detailWidth: 720)
        XCTAssertEqual(at720, 399)
        XCTAssertLessThanOrEqual(try XCTUnwrap(at720), 399)
        let at760 = IPadLayoutPolicy.detailLeftWidth(preferred: 600, detailWidth: 760)
        XCTAssertEqual(at760, 439)
        XCTAssertLessThanOrEqual(try XCTUnwrap(at760), 439)

        XCTAssertNil(IPadLayoutPolicy.detailLeftWidth(preferred: nil, detailWidth: 719))
        XCTAssertNil(IPadLayoutPolicy.detailLeftWidth(preferred: 450, detailWidth: 719))
    }

    func testSavedLeftWidthComesBackWhenThePanelWidens() {
        let saved: CGFloat = 470
        XCTAssertEqual(IPadLayoutPolicy.detailLeftWidth(preferred: saved, detailWidth: 760), 439)
        XCTAssertEqual(IPadLayoutPolicy.detailLeftWidth(preferred: saved, detailWidth: 1194), saved)
    }

    func testNonFiniteSavedWidthFallsBackToDefault() {
        XCTAssertEqual(IPadLayoutPolicy.detailLeftWidth(preferred: .nan, detailWidth: 873), 400)
        XCTAssertEqual(IPadLayoutPolicy.detailLeftWidth(preferred: .infinity, detailWidth: 873), 400)
    }

    // MARK: - One assistant entry (FR-021)

    func testAssistantToolbarButtonOnlyBesideTheSidebar() {
        // Sidebar shown: it hides the pinned «Ассистент» tab, ✦ is the entry.
        XCTAssertTrue(IPadLayoutPolicy.showsAssistantToolbarButton(layoutMode: .padRegular, tabBarIsSidebar: true))
        // Top tab bar: the pinned «Ассистент» tab is the entry, no second ✦.
        XCTAssertFalse(IPadLayoutPolicy.showsAssistantToolbarButton(layoutMode: .padRegular, tabBarIsSidebar: false))
        // Compact window and the iPhone: the phone bars, never ✦.
        XCTAssertFalse(IPadLayoutPolicy.showsAssistantToolbarButton(layoutMode: .phone, tabBarIsSidebar: false))
        XCTAssertFalse(IPadLayoutPolicy.showsAssistantToolbarButton(layoutMode: .phone, tabBarIsSidebar: true))
    }

    // MARK: - Recipe toolbar in the row of the top tab bar

    func testToolbarSharesTheTabBarRowOnlyUnderTheTopTabBar() {
        // iPad Pro 11": fresh launch 96 (own row), after reactivation 32 (the tab bar row).
        XCTAssertFalse(IPadLayoutPolicy.toolbarSharesTabBarRow(tabBarOnTop: true, splitTop: 96))
        XCTAssertTrue(IPadLayoutPolicy.toolbarSharesTabBarRow(tabBarOnTop: true, splitTop: 32))
        XCTAssertFalse(IPadLayoutPolicy.toolbarSharesTabBarRow(tabBarOnTop: true, splitTop: 64))
        XCTAssertTrue(IPadLayoutPolicy.toolbarSharesTabBarRow(tabBarOnTop: true, splitTop: 63))
        // Sidebar shown: there is no top tab bar to share a row with.
        XCTAssertFalse(IPadLayoutPolicy.toolbarSharesTabBarRow(tabBarOnTop: false, splitTop: 32))
    }

    func testToolbarBesideTheTabBarIsOneCapsuleBelow1100() {
        func style(_ width: CGFloat, beside: Bool) -> IPadDetailToolbarStyle {
            IPadLayoutPolicy.resolve(
                contentWidth: width,
                contentHeight: 1210,
                recipeExpanded: true,
                isEditing: false,
                toolbarBesideTabBar: beside
            ).toolbarStyle
        }
        // Portrait 11" and 13": no room beside the tab bar for the wide toolbar.
        XCTAssertEqual(style(834, beside: true), .padBesideTabBar)
        XCTAssertEqual(style(1032, beside: true), .padBesideTabBar)
        XCTAssertEqual(style(1099, beside: true), .padBesideTabBar)
        // Landscape: the usual thresholds.
        XCTAssertEqual(style(1100, beside: true), .padWide)
        XCTAssertEqual(style(1194, beside: true), .padWide)
        // Own row: the usual thresholds at any width.
        XCTAssertEqual(style(834, beside: false), .padWide)
        XCTAssertEqual(style(599, beside: false), .padNarrow)
    }

    func testFormSheetHeight() {
        XCTAssertEqual(IPadLayoutMetrics.formSheetHeight(containerHeight: 1194), 720)
        XCTAssertEqual(IPadLayoutMetrics.formSheetHeight(containerHeight: 744), 664)
    }

    // MARK: - «Развернуть» and the sidebar (T024)

    func testExpandHidesAShownSidebarAndRemembersOnlyOneBesideTheContent() {
        let beside = IPadLayoutPolicy.recipeExpandSidebar(shown: true, overlaysContent: false)
        XCTAssertTrue(beside.hide)
        XCTAssertTrue(beside.rememberHidden)
        // Portrait: a floating sidebar is closed and not brought back.
        let floating = IPadLayoutPolicy.recipeExpandSidebar(shown: true, overlaysContent: true)
        XCTAssertTrue(floating.hide)
        XCTAssertFalse(floating.rememberHidden)
        let hidden = IPadLayoutPolicy.recipeExpandSidebar(shown: false, overlaysContent: false)
        XCTAssertFalse(hidden.hide)
        XCTAssertFalse(hidden.rememberHidden)
    }

    /// No room for the list beside the recipe (push) or a compact window: no expanded recipe.
    func testRecipeStaysExpandedOnlyWhileTheSplitFitsInARegularWindow() {
        XCTAssertTrue(IPadLayoutPolicy.keepsRecipeExpanded(splitFits: true, isPadRegular: true))
        XCTAssertFalse(IPadLayoutPolicy.keepsRecipeExpanded(splitFits: false, isPadRegular: true))
        XCTAssertFalse(IPadLayoutPolicy.keepsRecipeExpanded(splitFits: true, isPadRegular: false))
        // The push threshold the split view feeds in: 640 pt of content is too narrow.
        XCTAssertFalse(layout(640).splitFits)
        XCTAssertTrue(layout(641).splitFits)
    }

    func testSidebarHiddenByExpandComesBackOnlyCollapsedOnRecipesInARegularWindow() {
        func restores(_ hidden: Bool, expanded: Bool = false, recipes: Bool = true, regular: Bool = true) -> Bool {
            IPadLayoutPolicy.restoresSidebarHiddenByExpand(
                hiddenByExpand: hidden,
                recipeExpanded: expanded,
                recipesTabSelected: recipes,
                isPadRegular: regular
            )
        }
        XCTAssertTrue(restores(true))
        XCTAssertFalse(restores(false), "Only a sidebar the expand hid comes back")
        XCTAssertFalse(restores(true, expanded: true))
        XCTAssertFalse(restores(true, recipes: false), "Not on another tab")
        XCTAssertFalse(restores(true, regular: false), "Not in a compact window")
    }

    func testSidebarShownAgainIsNoLongerOursToRestore() {
        XCTAssertFalse(IPadLayoutPolicy.sidebarStillHiddenByExpand(hiddenByExpand: true, sidebarShown: true))
        XCTAssertTrue(IPadLayoutPolicy.sidebarStillHiddenByExpand(hiddenByExpand: true, sidebarShown: false))
        XCTAssertFalse(IPadLayoutPolicy.sidebarStillHiddenByExpand(hiddenByExpand: false, sidebarShown: false))
    }
}
