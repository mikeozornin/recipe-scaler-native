import RecipeScalerCore
import SwiftUI

/// The Recipes section on `.padRegular` (spec 081, T024, plan.md Р5 variant B): the list
/// column and the recipe panel, two `NavigationStack`s in an `HStack` — never
/// `NavigationSplitView` (its column toolbars slide under the tab bar after the sidebar
/// toggles, spike S4).
///
/// As Apple Notes: the list column is always beside the recipe while there is room
/// (`IPadLayoutPolicy.resolve`, half in portrait, a third in landscape); «Развернуть» at the
/// leading edge of the recipe toolbar gives the recipe the whole section and hides the
/// sidebar, «Свернуть» brings both back. Without room for both the section is the phone
/// stack (push).
///
/// The selection lives in `AppShellCoordinator.recipesPath` (`RecipesSelection`), so the
/// open recipe survives rotation, a size class change and the phone stack (FR-018).
/// Dependencies are passed in explicitly (iOS 26 fallback environment, see `RecipeListView`).
struct IPadRecipesSplitView: View {
    @Bindable var coordinator: AppShellCoordinator
    let syncService: YjsSyncService
    let assistantRecipeContext: AssistantRecipeContext
    let timerManager: TimerManager
    let apiClient: APIClient
    let appContainer: AppContainer?
    let systemBannerStore: SystemBannerStore
    let mobileTimerPanelIsCollapsed: Bool
    let scenePhase: ScenePhase
    /// The tab bar is the top bar (sidebar hidden): the column title becomes the collection menu.
    let showsCollectionMenu: Bool
    /// ✦ in the recipe toolbar: the sidebar is shown, so the pinned «Ассистент» tab is not
    /// (`IPadLayoutPolicy.showsAssistantToolbarButton`).
    let showsAssistantToolbarButton: Bool

    @State private var searchText = ""

    private var selection: RecipesSelection {
        RecipesSelection.selection(from: coordinator.recipesPath)
    }

    private var index: CollectionRecipesIndex {
        syncService.collectionIndex
    }

    /// Nothing to expand without an open recipe: the list stays.
    private var isExpanded: Bool {
        coordinator.recipeDetailExpanded && selection.recipeId != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = IPadLayoutPolicy.resolve(
                contentWidth: proxy.size.width,
                contentHeight: proxy.size.height,
                recipeExpanded: isExpanded,
                isEditing: false,
                toolbarBesideTabBar: IPadLayoutPolicy.toolbarSharesTabBarRow(
                    tabBarOnTop: showsCollectionMenu,
                    splitTop: proxy.frame(in: .global).minY
                )
            )
            if layout.splitFits {
                split(layout: layout)
            } else {
                pushStack
            }
        }
        .onChange(of: selection.collectionId) { _, _ in
            searchText = ""
        }
        .onChange(of: selection.recipeId == nil) { _, isEmpty in
            // An empty collection opened from the sidebar: back to the list, not a blank panel.
            if isEmpty, coordinator.recipeDetailExpanded {
                setExpanded(false)
            }
        }
    }

    /// Expanded, the list column slides off the leading edge but stays in the hierarchy:
    /// without it iPadOS moves the recipe bar into the row of the top tab bar, and after
    /// «Свернуть» that bar keeps the narrow room beside the tab bar (items go to «More»).
    /// `accessibilityHidden` takes its bar items and row contents out of the VoiceOver tree;
    /// XCUITest still lists the off-screen rows.
    private func split(layout: IPadLayout) -> some View {
        let selection = selection
        return HStack(spacing: 0) {
            listColumn(selection: selection, width: layout.listWidth)
                .frame(width: layout.listWidth)
                .opacity(layout.listShown ? 1 : 0)
                .allowsHitTesting(layout.listShown)
                .accessibilityHidden(!layout.listShown)
            Rectangle()
                .fill(Color(.separator))
                .frame(width: IPadLayoutMetrics.columnDividerWidth)
                .ignoresSafeArea(edges: .vertical)
            detailPanel(selection: selection, layout: layout)
                .frame(width: layout.detailWidth)
        }
        .frame(width: layout.contentWidth, alignment: .trailing)
        .onAppear {
            repairSelection(previous: nil)
        }
        .onChange(of: coordinator.recipesPath) { _, _ in
            repairSelection(previous: nil)
        }
        .onChange(of: RepairInput(
            liveRecipeIds: index.live.map(\.id),
            listRecipeIds: listRecipeIds(selection.collectionId),
            userFolderIds: userFolderIds
        )) { previous, _ in
            repairSelection(previous: previous)
        }
    }

    /// No room for the list beside the recipe: the phone stack, nothing selected for the
    /// user (`repairSelection` runs in the split only).
    private var pushStack: some View {
        RecipeListView(
            navigationPath: $coordinator.recipesPath,
            syncService: syncService,
            coordinator: coordinator,
            assistantRecipeContext: assistantRecipeContext,
            timerManager: timerManager,
            apiClient: apiClient,
            appContainer: appContainer,
            systemBannerStore: systemBannerStore,
            mobileTimerPanelIsCollapsed: mobileTimerPanelIsCollapsed,
            scenePhase: scenePhase
        )
    }

    // MARK: - List column

    private func listColumn(selection: RecipesSelection, width: CGFloat) -> some View {
        let column = RecipeListColumn(
            selectedRecipeId: selection.recipeId,
            searchText: $searchText,
            selectRecipe: selectRecipe,
            collectionMenu: showsCollectionMenu
                ? RecipeListCollectionMenu(
                    collections: RecipeFolder.sortedActive(syncService.folders),
                    selectedCollectionId: selection.collectionId,
                    select: selectCollection
                )
                : nil,
            titleMaxWidth: max(0, width - IPadLayoutMetrics.listTitleBarReserve)
        )
        return NavigationStack {
            if let collectionId = selection.collectionId {
                CollectionFolderView(
                    folderId: collectionId,
                    syncService: syncService,
                    coordinator: coordinator,
                    timerManager: timerManager,
                    mobileTimerPanelIsCollapsed: mobileTimerPanelIsCollapsed,
                    navigationPath: .constant([]),
                    column: column
                )
            } else {
                RecipeListView(
                    syncService: syncService,
                    coordinator: coordinator,
                    assistantRecipeContext: assistantRecipeContext,
                    timerManager: timerManager,
                    apiClient: apiClient,
                    appContainer: appContainer,
                    systemBannerStore: systemBannerStore,
                    mobileTimerPanelIsCollapsed: mobileTimerPanelIsCollapsed,
                    scenePhase: scenePhase,
                    column: column
                )
            }
        }
        .id(selection.collectionId ?? CollectionVirtualFolders.allRecipesFolderId)
        .accessibilityIdentifier(AccessibilityIdentifiers.ipadRecipeListColumn)
    }

    // MARK: - Recipe panel

    private func detailPanel(selection: RecipesSelection, layout: IPadLayout) -> some View {
        NavigationStack {
            Group {
                if let recipeId = selection.recipeId {
                    YDocRecipeDetailView(
                        recipeId: recipeId,
                        startInEditMode: selection.openInEditMode,
                        syncService: syncService,
                        assistantRecipeContext: assistantRecipeContext,
                        timerManager: timerManager,
                        apiClient: apiClient,
                        appContainer: appContainer,
                        // A deleted recipe is replaced by the next one (`repairSelection`).
                        onDismiss: {},
                        scenePhase: scenePhase,
                        padPanel: RecipeDetailPadPanel(
                            detailWidth: layout.detailWidth,
                            toolbarStyle: layout.toolbarStyle,
                            assistantCoordinator: showsAssistantToolbarButton ? coordinator : nil
                        )
                    )
                    .id(recipeId)
                } else {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                        .accessibilityIdentifier(AccessibilityIdentifiers.ipadRecipeDetailPanel)
                }
            }
            .toolbar {
                if layout.showsExpandButton, selection.recipeId != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        expandButton
                    }
                }
            }
        }
    }

    /// Notes: `arrow.up.left.and.arrow.down.right` expands, the inward arrows collapse.
    private var expandButton: some View {
        let expanded = isExpanded
        return Button {
            setExpanded(!expanded)
        } label: {
            AppToolbarStyle.iconOnly(
                systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            )
        }
        .appToolbarIconButton()
        .accessibilityLabel(Text(expanded ? "ipad.recipes.collapse" : "ipad.recipes.expand"))
        .accessibilityIdentifier(AccessibilityIdentifiers.ipadRecipeExpandButton)
    }

    // MARK: - Selection

    private var userFolderIds: [String] {
        syncService.folders.filter { !$0.deleted }.map(\.id)
    }

    private func listRecipeIds(_ collectionId: String?) -> [String] {
        index.entries(inList: collectionId).map(\.id)
    }

    private func selectRecipe(_ recipeId: String, folderContext: String?, openInEditMode: Bool) {
        coordinator.recipesPath = RecipesSelection.selectingRecipe(
            recipeId,
            in: coordinator.recipesPath,
            folderContext: folderContext,
            openInEditMode: openInEditMode
        )
    }

    /// The title menu: a collection with its first recipe open, or «Все рецепты» with
    /// the open recipe kept (prototype `coll`).
    private func selectCollection(_ collectionId: String?) {
        if let collectionId {
            coordinator.recipesPath = IPadShellSelection.recipesPath(
                forCollection: collectionId,
                isSplitActive: true,
                firstRecipeId: listRecipeIds(collectionId).first
            )
        } else {
            coordinator.recipesPath = RecipesSelection.selectingAllRecipes(in: coordinator.recipesPath)
        }
    }

    /// «Развернуть» hides the sidebar beside the content too; «Свернуть» shows it again.
    /// A sidebar floating over the content (portrait) is closed and not brought back.
    private func setExpanded(_ expanded: Bool) {
        guard expanded != coordinator.recipeDetailExpanded else { return }
        if #available(iOS 26.2, *) {
            if expanded {
                let shown = IPadSidebarControl.isSidebarShown
                coordinator.sidebarHiddenByRecipeExpand = shown && !IPadSidebarControl.sidebarOverlaysContent
                if shown {
                    IPadSidebarControl.setSidebarHidden(true)
                }
            } else if coordinator.sidebarHiddenByRecipeExpand {
                IPadSidebarControl.setSidebarHidden(false)
            }
        }
        if !expanded {
            coordinator.sidebarHiddenByRecipeExpand = false
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            coordinator.recipeDetailExpanded = expanded
        }
    }

    /// T028: first recipe when nothing is open, the next one when the open one is
    /// deleted, «Все рецепты» when the collection is deleted; deep links canonicalized.
    private func repairSelection(previous: RepairInput?) {
        let path = coordinator.recipesPath
        let live = Set(index.live.map(\.id))
        guard let repaired = RecipesSelection.splitRepairedPath(
            path,
            userFolderIds: userFolderIds,
            liveRecipeIds: live,
            previousLiveRecipeIds: previous.map { Set($0.liveRecipeIds) } ?? [],
            listRecipeIds: listRecipeIds,
            previousListRecipeIds: previous?.listRecipeIds ?? []
        ) else { return }
        coordinator.recipesPath = repaired
    }

    private struct RepairInput: Equatable {
        let liveRecipeIds: [String]
        let listRecipeIds: [String]
        let userFolderIds: [String]
    }
}
