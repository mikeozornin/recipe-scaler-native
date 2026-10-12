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
    /// Recipe list column, without its divider: never narrower than this.
    static let listColumnMinWidth: CGFloat = 320
    /// Share of the content (minus the divider) the list column takes in portrait:
    /// list and recipe split it in half.
    static let listShareInPortrait: CGFloat = 1.0 / 2.0
    /// … and in landscape: list ⅓, recipe ⅔ (as Apple Notes).
    static let listShareInLandscape: CGFloat = 1.0 / 3.0
    /// Hairline between columns (list | detail, recipe left | right).
    static let columnDividerWidth: CGFloat = 1
    /// The list column stays beside the recipe only while the recipe keeps at least this
    /// much; narrower, the section is the phone stack (push).
    static let minDetailWithList: CGFloat = 320
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
    /// Top edge of the Recipes split in the window. Below it the panel toolbars share the
    /// row of the floating top tab bar (status bar + 8, as «Покупки» does); at or above it
    /// they sit in their own row under the tab bar (status bar + tab bar + 20 ≈ 96).
    static let separateToolbarRowMinTop: CGFloat = 64
    /// Sharing the tab bar row, the wide recipe toolbar fits beside the tab bar only from
    /// this content width (landscape); narrower windows get `.padBesideTabBar`.
    static let wideToolbarBesideTabBarMinContent: CGFloat = 1100
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
/// ✦ is not part of the style: see `IPadLayoutPolicy.showsAssistantToolbarButton`.
enum IPadDetailToolbarStyle: Equatable {
    /// «…», «Поделиться», «Не гасить экран», ✦, «Изменить» with text.
    case padWide
    /// «…», «Не гасить экран», ✦, a pencil without text.
    case padNarrow
    /// One capsule «…», «Не гасить экран», pencil: the toolbar shares the row of the
    /// floating top tab bar and only the room beside it is left (no ✦ there, FR-021).
    case padBesideTabBar
}

/// What the Recipes section shows at a given content size (layout.md §Токены, formulas).
struct IPadLayout: Equatable {
    let contentWidth: CGFloat
    /// Room for the list column beside the recipe; else the phone stack (push).
    let splitFits: Bool
    /// The list column is on screen: the split fits and the recipe is not expanded.
    let listShown: Bool
    /// List column width without its divider. Kept while the recipe is expanded (the
    /// column waits off screen); 0 for the phone stack.
    let listWidth: CGFloat
    let detailWidth: CGFloat
    let twoColumns: Bool
    let toolbarStyle: IPadDetailToolbarStyle
    /// «Развернуть» / «Свернуть» leads the recipe toolbar (the view adds: a recipe is open).
    let showsExpandButton: Bool
    let shopVkusvillIconOnly: Bool
}

/// Pure layout decisions for `.padRegular`. The app measures the content
/// (`GeometryReader`); tests derive it from the window size.
enum IPadLayoutPolicy {
    /// `W − sidebar − inspector` — the acceptance matrix and tests only.
    static func contentWidth(windowWidth: CGFloat, sidebarVisible: Bool, inspectorVisible: Bool) -> CGFloat {
        windowWidth
            - (sidebarVisible ? IPadLayoutMetrics.sidebarWidth : 0)
            - (inspectorVisible ? IPadLayoutMetrics.inspectorWidth : 0)
    }

    /// List column width, without its divider: half of the content in portrait (taller
    /// than wide), a third in landscape, never under 320. With the sidebar beside the
    /// content the rule applies to what is left of the window.
    static func listColumnWidth(contentWidth: CGFloat, contentHeight: CGFloat) -> CGFloat {
        let isPortrait = contentHeight > contentWidth
        let share = isPortrait ? IPadLayoutMetrics.listShareInPortrait : IPadLayoutMetrics.listShareInLandscape
        let proportional = ((contentWidth - IPadLayoutMetrics.columnDividerWidth) * share).rounded()
        return max(IPadLayoutMetrics.listColumnMinWidth, proportional)
    }

    /// `recipeExpanded`: the user expanded the recipe over the whole content (Notes-style).
    /// `toolbarBesideTabBar`: the panel toolbar shares the row of the floating top tab bar
    /// (`toolbarSharesTabBarRow`), so only the room beside the tab bar is left for it.
    static func resolve(
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        recipeExpanded: Bool,
        isEditing: Bool,
        toolbarBesideTabBar: Bool = false
    ) -> IPadLayout {
        let listWidth = listColumnWidth(contentWidth: contentWidth, contentHeight: contentHeight)
        let splitFits = contentWidth - listWidth - IPadLayoutMetrics.columnDividerWidth
            >= IPadLayoutMetrics.minDetailWithList
        let listShown = splitFits && !recipeExpanded && !isEditing
        let detailWidth = listShown
            ? contentWidth - listWidth - IPadLayoutMetrics.columnDividerWidth
            : contentWidth
        let toolbarStyle: IPadDetailToolbarStyle
        // With the list column shown the system keeps both column bars in their own row.
        if toolbarBesideTabBar, !listShown, contentWidth < IPadLayoutMetrics.wideToolbarBesideTabBarMinContent {
            toolbarStyle = .padBesideTabBar
        } else if detailWidth >= IPadLayoutMetrics.wideToolbarMinDetail {
            toolbarStyle = .padWide
        } else {
            toolbarStyle = .padNarrow
        }
        return IPadLayout(
            contentWidth: contentWidth,
            splitFits: splitFits,
            listShown: listShown,
            listWidth: splitFits ? listWidth : 0,
            detailWidth: detailWidth,
            twoColumns: detailWidth >= IPadLayoutMetrics.twoColumnMinDetail,
            toolbarStyle: toolbarStyle,
            showsExpandButton: splitFits && !isEditing,
            shopVkusvillIconOnly: contentWidth < IPadLayoutMetrics.shopLabeledMinContent
        )
    }

    /// iPadOS 26 puts a page's navigation bar into the row of the floating top tab bar
    /// (as on «Покупки»). The two stacks of the Recipes split get that row only after the
    /// scene reactivates or the sidebar toggles; on a fresh launch they keep their own row.
    /// `splitTop` is the split's top edge in the window.
    static func toolbarSharesTabBarRow(tabBarOnTop: Bool, splitTop: CGFloat) -> Bool {
        tabBarOnTop && splitTop < IPadLayoutMetrics.separateToolbarRowMinTop
    }

    /// ✦ in the toolbars of «Покупки», «Подборки» and the recipe panel (FR-007, FR-013,
    /// FR-021): exactly one assistant entry on screen. The top tab bar carries the pinned
    /// «Ассистент» tab, so ✦ shows only while the tab bar is the sidebar, which hides
    /// «Профиль» and «Ассистент». A compact window keeps the phone bars, without ✦.
    /// `tabBarIsSidebar` is `\.tabBarPlacement == .sidebar`, read by the shell.
    static func showsAssistantToolbarButton(layoutMode: AppLayoutMode, tabBarIsSidebar: Bool) -> Bool {
        layoutMode == .padRegular && tabBarIsSidebar
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
