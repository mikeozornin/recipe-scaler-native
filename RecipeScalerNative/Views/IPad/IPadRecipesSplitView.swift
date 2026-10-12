import RecipeScalerCore
import SwiftUI

/// The Recipes section on `.padRegular` (spec 081, T024, plan.md Р5 variant B): the list
/// column and the recipe panel, two `NavigationStack`s in an `HStack` — never
/// `NavigationSplitView` (its column toolbars slide under the tab bar after the sidebar
/// toggles, spike S4).
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

    @State private var searchText = ""
    @State private var isOverlayShown = false

    private enum ListMode {
        /// The 320 pt column beside the recipe.
        case inline
        /// Only the recipe; «Список рецептов» in its toolbar.
        case hidden
        /// The list over the recipe with dimming (too narrow for the column).
        case overlay
    }

    private var selection: RecipesSelection {
        RecipesSelection.selection(from: coordinator.recipesPath)
    }

    private var index: CollectionRecipesIndex {
        syncService.collectionIndex
    }

    var body: some View {
        GeometryReader { proxy in
            split(layout: IPadLayoutPolicy.resolve(
                contentWidth: proxy.size.width,
                listCollapsedByUser: coordinator.recipesListHiddenByUser,
                isEditing: false
            ))
        }
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
        .onChange(of: selection.collectionId) { _, _ in
            searchText = ""
        }
    }

    private func split(layout: IPadLayout) -> some View {
        let selection = selection
        // Nothing to show in the panel (an empty collection): the list stays over it.
        let listMode: ListMode = layout.listShown
            ? .inline
            : (isOverlayShown || selection.recipeId == nil ? .overlay : .hidden)
        return HStack(spacing: 0) {
            if listMode == .inline {
                listColumn(selection: selection)
                    .frame(width: IPadLayoutMetrics.listColumnWidth)
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: IPadLayoutMetrics.columnDividerWidth)
                    .ignoresSafeArea(edges: .vertical)
            }
            detailPanel(selection: selection, layout: layout)
                .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .leading) {
            if listMode == .overlay {
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { isOverlayShown = false }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(Text("common.close"))
                        .accessibilityIdentifier(AccessibilityIdentifiers.ipadRecipeListDim)
                    listColumn(selection: selection)
                        .frame(width: IPadLayoutMetrics.listColumnWidth)
                        .background(Color(.systemBackground).ignoresSafeArea())
                        .shadow(radius: 12)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: listMode)
        .onChange(of: layout.listShown) { _, shown in
            if shown { isOverlayShown = false }
        }
    }

    // MARK: - List column

    private func listColumn(selection: RecipesSelection) -> some View {
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
                : nil
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
                        scenePhase: scenePhase
                    )
                    .id(recipeId)
                } else {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                        .accessibilityIdentifier(AccessibilityIdentifiers.ipadRecipeDetailPanel)
                }
            }
            .toolbar {
                if layout.showsListButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showList(contentWidth: layout.contentWidth)
                        } label: {
                            AppToolbarStyle.iconOnly(systemName: "sidebar.left")
                        }
                        .appToolbarIconButton()
                        .accessibilityLabel(Text("ipad.recipes.show-list"))
                        .accessibilityIdentifier(AccessibilityIdentifiers.ipadShowRecipeListButton)
                    }
                }
            }
        }
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
        isOverlayShown = false
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

    /// «Список рецептов»: back to the column when it fits, else the list over the recipe.
    private func showList(contentWidth: CGFloat) {
        let fits = IPadLayoutPolicy.resolve(
            contentWidth: contentWidth,
            listCollapsedByUser: false,
            isEditing: false
        ).listShown
        if fits {
            coordinator.recipesListHiddenByUser = false
        } else {
            isOverlayShown = true
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
