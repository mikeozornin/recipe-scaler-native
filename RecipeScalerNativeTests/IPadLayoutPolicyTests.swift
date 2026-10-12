//
//  IPadLayoutPolicyTests.swift
//
//  Spec 081 (T007) — iPad layout policy against layout.md §Токены and §Матрица приёмки.
//

import CoreGraphics
import XCTest
@testable import RecipeScalerNative

final class IPadLayoutPolicyTests: XCTestCase {

    private func layout(
        _ contentWidth: CGFloat,
        listCollapsedByUser: Bool = false,
        isEditing: Bool = false
    ) -> IPadLayout {
        IPadLayoutPolicy.resolve(
            contentWidth: contentWidth,
            listCollapsedByUser: listCollapsedByUser,
            isEditing: isEditing
        )
    }

    // MARK: - Thresholds (value and 1 pt below)

    func testListThresholdAt881() {
        let atThreshold = layout(560 + 321)
        XCTAssertTrue(atThreshold.listShown)
        XCTAssertEqual(atThreshold.detailWidth, 560)
        XCTAssertFalse(atThreshold.showsListButton)

        let below = layout(560 + 321 - 1)
        XCTAssertFalse(below.listShown)
        XCTAssertEqual(below.detailWidth, 880)
        XCTAssertTrue(below.showsListButton)
    }

    func testTwoColumnThresholdAt720() {
        XCTAssertTrue(layout(720).twoColumns)
        XCTAssertFalse(layout(719).twoColumns)
        // With the list shown the panel is what counts: 720 + 321 → two columns, 1 pt less → one.
        XCTAssertTrue(layout(720 + 321).twoColumns)
        XCTAssertFalse(layout(720 + 321 - 1).twoColumns)
    }

    func testWideToolbarThresholdAt600() {
        XCTAssertEqual(layout(600).toolbarStyle, .padWide)
        XCTAssertEqual(layout(599).toolbarStyle, .padNarrow)
    }

    func testVkusvillLabelThresholdAt640() {
        XCTAssertFalse(layout(640).shopVkusvillIconOnly)
        XCTAssertTrue(layout(639).shopVkusvillIconOnly)
    }

    func testCollapsedListAndEditingHideTheList() {
        let collapsed = layout(1194, listCollapsedByUser: true)
        XCTAssertFalse(collapsed.listShown)
        XCTAssertEqual(collapsed.detailWidth, 1194)
        XCTAssertTrue(collapsed.showsListButton)

        // layout.md §Матрица приёмки: edit mode hides the list, the panel takes the content.
        for width: CGFloat in [1194, 776, 834] {
            let editing = layout(width, isEditing: true)
            XCTAssertFalse(editing.listShown, "W=\(width)")
            XCTAssertEqual(editing.detailWidth, width, "W=\(width)")
            XCTAssertTrue(editing.twoColumns, "W=\(width)")
        }
    }

    // MARK: - layout.md §Матрица приёмки

    private struct MatrixRow {
        let window: CGFloat
        let sidebar: Bool
        let inspector: Bool
        let content: CGFloat
        let list: Bool
        let detail: CGFloat
        let twoColumns: Bool
        let toolbar: IPadDetailToolbarStyle
        let vkusvillIconOnly: Bool
    }

    func testPrototypeMatrix() {
        let rows: [MatrixRow] = [
            // Landscape, full screen.
            MatrixRow(window: 1194, sidebar: true, inspector: false, content: 914, list: true, detail: 593,
                      twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: false),
            MatrixRow(window: 1194, sidebar: false, inspector: false, content: 1194, list: true, detail: 873,
                      twoColumns: true, toolbar: .padWide, vkusvillIconOnly: false),
            MatrixRow(window: 1194, sidebar: true, inspector: true, content: 574, list: false, detail: 574,
                      twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: true),
            MatrixRow(window: 1194, sidebar: false, inspector: true, content: 854, list: false, detail: 854,
                      twoColumns: true, toolbar: .padWide, vkusvillIconOnly: false),
            // Landscape, 2/3.
            MatrixRow(window: 776, sidebar: true, inspector: false, content: 496, list: false, detail: 496,
                      twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: true),
            MatrixRow(window: 776, sidebar: false, inspector: false, content: 776, list: false, detail: 776,
                      twoColumns: true, toolbar: .padWide, vkusvillIconOnly: false),
            MatrixRow(window: 776, sidebar: false, inspector: true, content: 436, list: false, detail: 436,
                      twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: true),
            // Portrait, full screen.
            MatrixRow(window: 834, sidebar: true, inspector: false, content: 554, list: false, detail: 554,
                      twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: true),
            MatrixRow(window: 834, sidebar: false, inspector: false, content: 834, list: false, detail: 834,
                      twoColumns: true, toolbar: .padWide, vkusvillIconOnly: false),
            MatrixRow(window: 834, sidebar: false, inspector: true, content: 494, list: false, detail: 494,
                      twoColumns: false, toolbar: .padNarrow, vkusvillIconOnly: true),
            // 13-inch, full screen.
            MatrixRow(window: 1376, sidebar: true, inspector: false, content: 1096, list: true, detail: 775,
                      twoColumns: true, toolbar: .padWide, vkusvillIconOnly: false),
            MatrixRow(window: 1032, sidebar: true, inspector: false, content: 752, list: false, detail: 752,
                      twoColumns: true, toolbar: .padWide, vkusvillIconOnly: false),
        ]
        for row in rows {
            let label = "W=\(row.window) sidebar=\(row.sidebar) inspector=\(row.inspector)"
            let content = IPadLayoutPolicy.contentWidth(
                windowWidth: row.window,
                sidebarVisible: row.sidebar,
                inspectorVisible: row.inspector
            )
            XCTAssertEqual(content, row.content, label)
            let resolved = layout(content)
            XCTAssertEqual(resolved.contentWidth, row.content, label)
            XCTAssertEqual(resolved.listShown, row.list, label)
            XCTAssertEqual(resolved.detailWidth, row.detail, label)
            XCTAssertEqual(resolved.twoColumns, row.twoColumns, label)
            XCTAssertEqual(resolved.toolbarStyle, row.toolbar, label)
            XCTAssertEqual(resolved.showsListButton, !row.list, label)
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
    /// here (list hidden, one column); the on-screen verdict belongs to T049.
    func testMatrixEdgeRowsKeepFormulaValues() {
        for (window, content): (CGFloat, CGFloat) in [(776, 156), (834, 214)] {
            let width = IPadLayoutPolicy.contentWidth(windowWidth: window, sidebarVisible: true, inspectorVisible: true)
            XCTAssertEqual(width, content)
            let resolved = layout(width)
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
        for width: CGFloat in [1194, 776, 834, 1376, 1032] {
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

    func testFormSheetHeight() {
        XCTAssertEqual(IPadLayoutMetrics.formSheetHeight(containerHeight: 1194), 720)
        XCTAssertEqual(IPadLayoutMetrics.formSheetHeight(containerHeight: 744), 664)
    }
}
