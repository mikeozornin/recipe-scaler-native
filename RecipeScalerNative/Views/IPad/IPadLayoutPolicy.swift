import CoreGraphics

/// iPad layout tokens (spec 081, `specs/081-ipad-adaptation/layout.md` §Токены).
/// Numbers in pt. iPad views take sizes only from here.
enum IPadLayoutMetrics {
    /// Wide window, for reference only: the horizontal size class decides (`AppLayoutMode`).
    static let regularMinWidth: CGFloat = 680
    /// Sidebar (272) plus its 8 pt inset; subtracted from the content width while visible.
    static let sidebarWidth: CGFloat = 280
    /// Leading safe-area inset of the selected page below which a shown sidebar floats
    /// over the content instead of standing beside it (spike S1/S2, `IPadSidebarControl`).
    static let sidebarOverlayMaxLeadingInset: CGFloat = 60
    /// Recipe list column, without its divider.
    static let listColumnWidth: CGFloat = 320
    /// Hairline between columns (list | detail, recipe left | right).
    static let columnDividerWidth: CGFloat = 1
    /// List column plus its divider: 321.
    static let listColumnTotalWidth: CGFloat = listColumnWidth + columnDividerWidth
    /// The list column is shown only if the detail panel keeps at least this much.
    static let minDetailWithList: CGFloat = 560
    /// `.inspectorColumnWidth` of the assistant.
    static let inspectorWidth: CGFloat = 340
    /// The recipe splits into two columns from this panel width.
    static let twoColumnMinDetail: CGFloat = 720
    /// Left recipe column until the user drags the divider.
    static let detailLeftWidth: CGFloat = 400
    static let detailLeftMinWidth: CGFloat = 320
    static let detailLeftMaxWidth: CGFloat = 480
    /// Steps column never gets narrower than this.
    static let detailRightMinWidth: CGFloat = 320
    /// Drag area of the recipe column divider (the visible line is `columnDividerWidth`).
    static let columnDividerHitWidth: CGFloat = 12
    /// VoiceOver adjustable step of the column divider.
    static let columnDividerAccessibilityStep: CGFloat = 20
    static let stepsMaxWidth: CGFloat = 660
    static let stepsHorizontalPadding: CGFloat = 32
    /// One-column recipe and edit form, centered.
    static let singleColumnMaxWidth: CGFloat = 720
    /// «Поделиться» and «Изменить» get text labels from this panel width.
    static let wideToolbarMinDetail: CGFloat = 600
    /// «Купить во Вкусвилле» keeps its text label from this content width.
    static let shopLabeledMinContent: CGFloat = 640
    /// «Покупки», «Профиль», the «Подборки» feed.
    static let readablePageWidth: CGFloat = 720
    /// Public author profile.
    static let authorPageWidth: CGFloat = 1100
    static let discoverSegmentWidth: CGFloat = 320
    static let formSheetWidth: CGFloat = 560
    static let formSheetMaxHeight: CGFloat = 720
    static let formSheetVerticalInset: CGFloat = 80
    static let timersPopoverWidth: CGFloat = 380
    static let collectionsPopoverWidth: CGFloat = 300
    static let historyPopoverWidth: CGFloat = inspectorWidth - 24
    static let historyPopoverMaxHeight: CGFloat = 420
    /// Panel toolbars (system bars).
    static let barHeight: CGFloat = 56
    /// `ScreenAwakeStatusBanner` strip.
    static let cookStripMinHeight: CGFloat = 44
    /// Avatar in the sidebar footer (`AccountView` keeps 40).
    static let footerAvatarSize: CGFloat = 36

    /// Saved left recipe column width (Q5): one per device, shared by view and edit mode.
    /// Written only when the divider is released; layout only reads and clamps it.
    static let detailLeftColumnWidthStorageKey = "ipad.recipeDetailLeftColumnWidth"

    /// Import form sheet height: 720 or less, keeping 40 pt above and below.
    static func formSheetHeight(containerHeight: CGFloat) -> CGFloat {
        min(formSheetMaxHeight, containerHeight - formSheetVerticalInset)
    }
}

/// Recipe detail toolbar on `.padRegular` (T026). The phone keeps its own toolbar.
enum IPadDetailToolbarStyle: Equatable {
    /// «…», «Поделиться», «Не гасить экран», ✦, «Изменить» with text.
    case padWide
    /// «…», «Не гасить экран», ✦, a pencil without text.
    case padNarrow
}

/// What the Recipes section shows at a given content width (layout.md §Токены, formulas).
struct IPadLayout: Equatable {
    let contentWidth: CGFloat
    let listShown: Bool
    let detailWidth: CGFloat
    let twoColumns: Bool
    let toolbarStyle: IPadDetailToolbarStyle
    let showsListButton: Bool
    let shopVkusvillIconOnly: Bool
}

/// Pure layout decisions for `.padRegular`. The app measures `contentWidth`
/// (`onGeometryChange` / `GeometryReader`); tests derive it from the window width.
enum IPadLayoutPolicy {
    /// `W − sidebar − inspector` — the acceptance matrix and tests only.
    static func contentWidth(windowWidth: CGFloat, sidebarVisible: Bool, inspectorVisible: Bool) -> CGFloat {
        windowWidth
            - (sidebarVisible ? IPadLayoutMetrics.sidebarWidth : 0)
            - (inspectorVisible ? IPadLayoutMetrics.inspectorWidth : 0)
    }

    static func resolve(contentWidth: CGFloat, listCollapsedByUser: Bool, isEditing: Bool) -> IPadLayout {
        let listShown = !listCollapsedByUser
            && !isEditing
            && contentWidth - IPadLayoutMetrics.listColumnTotalWidth >= IPadLayoutMetrics.minDetailWithList
        let detailWidth = contentWidth - (listShown ? IPadLayoutMetrics.listColumnTotalWidth : 0)
        return IPadLayout(
            contentWidth: contentWidth,
            listShown: listShown,
            detailWidth: detailWidth,
            twoColumns: detailWidth >= IPadLayoutMetrics.twoColumnMinDetail,
            toolbarStyle: detailWidth >= IPadLayoutMetrics.wideToolbarMinDetail ? .padWide : .padNarrow,
            showsListButton: !listShown,
            shopVkusvillIconOnly: contentWidth < IPadLayoutMetrics.shopLabeledMinContent
        )
    }

    /// Left recipe column width, or `nil` for one column.
    /// `clamp(preferred ?? 400, 320, min(480, detailWidth − 1 − 320))`: the saved width
    /// is never rewritten here, so it comes back once the panel is wide enough again.
    static func detailLeftWidth(preferred: CGFloat?, detailWidth: CGFloat) -> CGFloat? {
        guard detailWidth >= IPadLayoutMetrics.twoColumnMinDetail else { return nil }
        let upper = min(
            IPadLayoutMetrics.detailLeftMaxWidth,
            detailWidth - IPadLayoutMetrics.columnDividerWidth - IPadLayoutMetrics.detailRightMinWidth
        )
        let wanted = preferred.flatMap { $0.isFinite ? $0 : nil } ?? IPadLayoutMetrics.detailLeftWidth
        return min(max(wanted, IPadLayoutMetrics.detailLeftMinWidth), upper)
    }
}
