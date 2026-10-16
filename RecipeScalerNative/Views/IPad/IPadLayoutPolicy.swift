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
    /// Room the list column bar keeps beside its title: the bar margins, «+» and a gap.
    /// A longer title truncates; otherwise the bar sends the title menu and «+» to «More».
    static let listTitleBarReserve: CGFloat = 150
    /// Hairline between columns (list | detail, recipe left | right).
    static let columnDividerWidth: CGFloat = 1
    /// The list column stays beside the recipe only while the recipe keeps at least this
    /// much; narrower, the section is the phone stack (push).
    static let minDetailWithList: CGFloat = 320
    /// The assistant panel beside the tab view (`AppShellView.assistantPanel`, FR-019),
    /// without its divider.
    static let inspectorWidth: CGFloat = 340
    /// «Ассистент» at the leading edge of the panel bar (prototype `.insp-bar h3`): what
    /// [history, new chat] and × leave of the 340 pt row. Wider, × goes to «More»; a longer
    /// title scales down instead of truncating.
    static let inspectorTitleWidth: CGFloat = 120
    /// The recipe splits into two columns from this panel width.
    static let twoColumnMinDetail: CGFloat = 720
    /// Left recipe column: a fixed width, no divider to drag (owner decision 2026-10-13).
    static let detailLeftWidth: CGFloat = 400
    /// Steps column never gets narrower than this.
    static let detailRightMinWidth: CGFloat = 320
    static let stepsMaxWidth: CGFloat = 660
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
    /// «Покупки», «Профиль», the «Моя лента» feed.
    static let readablePageWidth: CGFloat = 720
    /// Public author profile.
    static let authorPageWidth: CGFloat = 1100
    /// «Подборки» with the author card grid (spec 082), as wide as the author page.
    static let discoverPageWidth: CGFloat = authorPageWidth
    static let discoverSegmentWidth: CGFloat = 320
    static let formSheetWidth: CGFloat = 560
    static let formSheetMaxHeight: CGFloat = 720
    static let formSheetVerticalInset: CGFloat = 80
    static let timersPopoverWidth: CGFloat = 380
    static let collectionsPopoverWidth: CGFloat = 300
    /// As the history popover: room for about six collections and «Новая коллекция».
    static let collectionsPopoverHeight: CGFloat = 420
    static let historyPopoverWidth: CGFloat = inspectorWidth - 24
    static let historyPopoverMaxHeight: CGFloat = 420
    /// Panel toolbars (system bars).
    static let barHeight: CGFloat = 56
    /// `ScreenAwakeStatusBanner` strip.
    static let cookStripMinHeight: CGFloat = 44
    /// Avatar in the sidebar footer (`AccountView` keeps 40).
    static let footerAvatarSize: CGFloat = 36

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
    /// The list column is on screen: the split fits, the recipe is neither expanded nor
    /// edited (US5) and the assistant panel does not stand beside it (FR-022).
    let listShown: Bool
    /// List column width without its divider. Kept while the recipe is expanded (the
    /// column waits off screen); 0 for the phone stack.
    let listWidth: CGFloat
    let detailWidth: CGFloat
    let twoColumns: Bool
    let toolbarStyle: IPadDetailToolbarStyle
    /// «Развернуть» / «Свернуть» leads the recipe toolbar (the view adds: a recipe is open).
    /// Not while the assistant panel is open: the expanded state waits for it to close.
    /// Not in edit either: the edit bar is «Готово» only (Q2).
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
    /// `contentHeight` is the height without the software keyboard
    /// (`contentHeightIgnoringKeyboard`): the keyboard never turns portrait into landscape.
    static func listColumnWidth(contentWidth: CGFloat, contentHeight: CGFloat) -> CGFloat {
        let isPortrait = contentHeight > contentWidth
        let share = isPortrait ? IPadLayoutMetrics.listShareInPortrait : IPadLayoutMetrics.listShareInLandscape
        let proportional = ((contentWidth - IPadLayoutMetrics.columnDividerWidth) * share).rounded()
        return max(IPadLayoutMetrics.listColumnMinWidth, proportional)
    }

    /// `recipeExpanded`: the user expanded the recipe over the whole content (Notes-style).
    /// `isEditing`: the open recipe is in edit (US5); edit takes the content like the
    /// expanded recipe (`expandsRecipeForEdit`).
    /// `toolbarBesideTabBar`: the panel toolbar shares the row of the floating top tab bar
    /// (`toolbarSharesTabBarRow`), so only the room beside the tab bar is left for it.
    /// `assistantPanelOpen`: the assistant panel stands beside the tab view (`contentWidth`
    /// already excludes it). Whether the section is the split or the phone stack is then
    /// decided on the width without the panel, with or without an open recipe: opening or
    /// closing the panel never swaps the recipe view (scroll, cooking) or collapses an
    /// expanded recipe, and picking a recipe under the panel never swaps the phone stack
    /// for the split. FR-022: beside an open recipe (`recipeOpen`) the list column hides at
    /// any width and the recipe takes the content. The split keeps a recipe open
    /// (`IPadRecipesSplitView.repairSelection`), so without one the list is empty and stays.
    static func resolve(
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        recipeExpanded: Bool,
        isEditing: Bool,
        toolbarBesideTabBar: Bool = false,
        assistantPanelOpen: Bool = false,
        recipeOpen: Bool = true
    ) -> IPadLayout {
        let listWidth = listColumnWidth(contentWidth: contentWidth, contentHeight: contentHeight)
        let splitFits: Bool
        if assistantPanelOpen {
            let widthWithoutPanel = contentWidth + IPadLayoutMetrics.inspectorWidth + IPadLayoutMetrics.columnDividerWidth
            splitFits = Self.splitFits(
                contentWidth: widthWithoutPanel,
                listWidth: listColumnWidth(contentWidth: widthWithoutPanel, contentHeight: contentHeight)
            )
        } else {
            splitFits = Self.splitFits(contentWidth: contentWidth, listWidth: listWidth)
        }
        let listShown = splitFits && !recipeExpanded && !isEditing && !(assistantPanelOpen && recipeOpen)
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
            showsExpandButton: splitFits && !isEditing && !assistantPanelOpen,
            shopVkusvillIconOnly: contentWidth < IPadLayoutMetrics.shopLabeledMinContent
        )
    }

    /// The height that decides portrait or landscape: the window's, as layout.md §Матрица
    /// приёмки counts it. A view laid out inside the safe area is shorter by the bars (the
    /// ⅔ landscape window 776 × 834 would turn landscape under them) and, while the keyboard
    /// is up, by the keyboard (portrait 834 × 1100 becomes 834 × 700), so the content is
    /// measured once more to the window's top and bottom edges (`withoutKeyboard`). The
    /// height alone differs: a measurement of another width is from before a rotation or
    /// resize and is not used.
    static func contentHeightIgnoringKeyboard(current: CGSize, withoutKeyboard: CGSize?) -> CGFloat {
        guard let withoutKeyboard, abs(withoutKeyboard.width - current.width) < 0.5 else {
            return current.height
        }
        return max(current.height, withoutKeyboard.height)
    }

    /// The list column fits beside a recipe of at least 320.
    private static func splitFits(contentWidth: CGFloat, listWidth: CGFloat) -> Bool {
        contentWidth - listWidth - IPadLayoutMetrics.columnDividerWidth >= IPadLayoutMetrics.minDetailWithList
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

    // MARK: - «Развернуть» and the sidebar (T024)

    /// «Развернуть» closes a shown sidebar. Only one standing beside the content is
    /// remembered and comes back on «Свернуть»; a sidebar floating over the content
    /// (portrait) is just closed. `hiddenByExpand`: an earlier expand hid the sidebar and
    /// its restore is still pending (the edit went through a compact window, T043); while
    /// the sidebar stays hidden it is still ours to bring back.
    static func recipeExpandSidebar(
        shown: Bool,
        overlaysContent: Bool,
        hiddenByExpand: Bool
    ) -> (hide: Bool, rememberHidden: Bool) {
        (hide: shown, rememberHidden: (shown && !overlaysContent) || (hiddenByExpand && !shown))
    }

    /// Edit takes the whole section (US5, T041): entering it in the split expands the
    /// recipe as «Развернуть» does, hiding the list and a sidebar beside the content, and
    /// both come back by the expand rules: the recipe stays expanded after «Готово» and
    /// «Свернуть» restores the list and the sidebar (`#recipes/focus`). The phone stack
    /// (push) shows no list and has no expanded state, so edit there changes nothing.
    static func expandsRecipeForEdit(isEditing: Bool, recipeExpanded: Bool, splitFits: Bool) -> Bool {
        isEditing && !recipeExpanded && splitFits
    }

    /// The expanded recipe lasts only while the list column could stand beside it: a
    /// window too narrow for the split (push) or compact collapses it.
    static func keepsRecipeExpanded(splitFits: Bool, isPadRegular: Bool) -> Bool {
        splitFits && isPadRegular
    }

    /// A sidebar hidden by «Развернуть» comes back once the recipe is collapsed, but only
    /// on the Recipes section of a regular window: collapsed elsewhere (another tab, a
    /// compact window) it waits until the user is back on Recipes in a wide window.
    /// Not while a recipe edit goes on (`recipeEditing`): back in a wide window the edit
    /// expands the recipe again (`expandsRecipeForEdit`), so the sidebar does not flash.
    static func restoresSidebarHiddenByExpand(
        hiddenByExpand: Bool,
        recipeExpanded: Bool,
        recipeEditing: Bool,
        recipesTabSelected: Bool,
        isPadRegular: Bool
    ) -> Bool {
        hiddenByExpand && !recipeExpanded && !recipeEditing && recipesTabSelected && isPadRegular
    }

    /// The sidebar showed up while it was hidden by «Развернуть» (the user's toggle, or the
    /// system after a rotation): nothing is left to restore, «Свернуть» leaves it alone.
    static func sidebarStillHiddenByExpand(hiddenByExpand: Bool, sidebarShown: Bool) -> Bool {
        hiddenByExpand && !sidebarShown
    }

    /// FR-018, T043: a recipes stack rebuilt by a layout change (the split turned into the
    /// phone stack, or a size class change) is popped by SwiftUI while the window reflows,
    /// about 150 ms after it appeared. Only a pop this soon after the rebuild is put back;
    /// the user's own «Назад» comes later, and with no rebuild nothing is put back.
    static let stackReflowWindow: Double = 0.5

    /// The path to put back when the rebuilt stack was emptied, or `nil`. `sinceRebuild` is
    /// the time in seconds since the layout change rebuilt the stack, `nil` without one. A recipe
    /// deleted meanwhile is not put back.
    static func stackPathToRestore(
        _ kept: [RecipesRoute],
        sinceRebuild: Double?,
        isRecipeLive: (String) -> Bool
    ) -> [RecipesRoute]? {
        guard !kept.isEmpty, let sinceRebuild, sinceRebuild >= 0, sinceRebuild < stackReflowWindow
        else { return nil }
        if let recipeId = RecipesSelection.selection(from: kept).recipeId, !isRecipeLive(recipeId) {
            return nil
        }
        return kept
    }

    /// Left recipe column width, or `nil` for one column:
    /// `min(400, detailWidth − 1 − 320)`, so 399 at the 720 pt threshold.
    static func detailLeftWidth(detailWidth: CGFloat) -> CGFloat? {
        guard detailWidth >= IPadLayoutMetrics.twoColumnMinDetail else { return nil }
        return min(
            IPadLayoutMetrics.detailLeftWidth,
            detailWidth - IPadLayoutMetrics.columnDividerWidth - IPadLayoutMetrics.detailRightMinWidth
        )
    }
}
