//
//  AppShellCoordinator.swift
//  RecipeScalerNative
//
//  Tab routing, deep-link orchestration, and modal presentation state for the app shell.
//

import SwiftUI
import RecipeScalerCore

struct ImportPresentation: Identifiable {
    let id = UUID()
}

struct WideRecipesState: Equatable {
    var selectedRecipeId: String?
    var activeFolderId: String?
    var listScrollOffset: CGFloat = 0
}

@MainActor
@Observable
final class AppShellCoordinator {
    private let syncService: YjsSyncService
    private let deepLinkRouter: DeepLinkRouter
    private let discoverListState: DiscoverListStateStore?

    /// Spec 057 — silent importer for incoming `.recipe` files via AirDrop /
    /// Files / Mail. Injected by `AppContainer` so test doubles can be passed
    /// in for unit testing; previews construct it lazily when they don't have
    /// a real container.
    ///
    /// `private(set)` would block `AppContainer` from wiring the
    /// `weak shellCoordinator` back-reference after both objects exist, so the
    /// setter is internal (module-scoped only).
    var fileImportCoordinator: RecipeFileImportCoordinator?

    var selectedTab: AppTab = .recipes
    var importPresentation: ImportPresentation?
    var recipesPath = NavigationPath()
    var discoverPath = NavigationPath()
    var shoppingPath = NavigationPath()
    var wideRecipesState = WideRecipesState()
    /// Set by `AdaptiveAppShell` when regular layout is active (recipe split selection).
    var usesRegularRecipeSplit = false
    private(set) var pendingSpotlightRecipeId: String?
    /// When true, Profile (`AccountView`) should scroll to Reminders, enable sync, and open list picker.
    private(set) var pendingRemindersSetup = false
    /// Spec 057 — last user-facing toast message from a silent file import.
    /// AppShellView renders this as a transient overlay.
    var pendingFileImportToast: String?

    init(
        syncService: YjsSyncService,
        deepLinkRouter: DeepLinkRouter,
        fileImportCoordinator: RecipeFileImportCoordinator? = nil,
        discoverListState: DiscoverListStateStore? = nil
    ) {
        self.syncService = syncService
        self.deepLinkRouter = deepLinkRouter
        self.fileImportCoordinator = fileImportCoordinator
        self.discoverListState = discoverListState
    }

    // MARK: - Tab selection

    func handleTabSelection(_ newTab: AppTab) {
        if newTab == .importTab {
            presentImport()
            return
        }
        if newTab == selectedTab {
            resetNestedNavigation(for: newTab)
        } else {
            selectedTab = newTab
        }
    }

    func handleSidebarSelection(_ newTab: AppTab) {
        handleTabSelection(newTab)
    }

    func presentImport() {
        importPresentation = ImportPresentation()
    }

    // MARK: - Shopping → Reminders setup CTA

    /// Switches to Profile and asks `AccountView` to enable Reminders + open list picker.
    func requestRemindersSetup() {
        pendingRemindersSetup = true
        selectedTab = .profile
    }

    func clearPendingRemindersSetup() {
        pendingRemindersSetup = false
    }

    // MARK: - Import completion

    /// Dismisses the import sheet, switches to Recipes, and optionally navigates to the imported recipe.
    /// Returns a localized toast message when import succeeded, otherwise `nil`.
    func completeImport(_ result: ImportRecipesResult) -> String? {
        importPresentation = nil
        selectedTab = .recipes
        if let id = result.primaryRecipeId {
            openRecipeDetail(recipeId: id)
        }
        guard result.importedCount > 0 else { return nil }
        return Bundle.appPluralizedString(key: "import.success", count: result.importedCount)
    }

    // MARK: - Legacy deep link (UserDefaults from Share/Action extensions)

    func consumePendingRecipeIdIfNeeded() {
        guard let id = DeepLinkRouter.consumePendingRecipeId() else { return }
        selectedTab = .recipes
        openRecipeDetail(recipeId: id)
    }

    // MARK: - Wide recipe split (043)

    func selectRecipeInWideSplit(_ recipeId: String?) {
        wideRecipesState.selectedRecipeId = recipeId
    }

    func openFolderInWideSplit(_ folderId: String?) {
        wideRecipesState.activeFolderId = folderId
    }

    func autoSelectFirstRecipeInWideSplitIfNeeded(entries: [CollectionEntry]) {
        guard usesRegularRecipeSplit, selectedTab == .recipes else { return }
        guard wideRecipesState.selectedRecipeId == nil else { return }
        let sorted = RecipeTitleEmoji.sortCollectionEntries(entries).filter { !$0.deleted }
        guard let first = sorted.first else { return }
        wideRecipesState.selectedRecipeId = first.id
    }

    func openRecipeDetail(recipeId: String) {
        if usesRegularRecipeSplit {
            wideRecipesState.selectedRecipeId = recipeId
        } else {
            recipesPath.append(RecipesRoute.recipe(recipeId: recipeId, folderContext: nil))
        }
    }

    // MARK: - Deep linking (Spotlight, URL scheme, Universal Links)

    func handleDeepLink(_ link: DeepLink) {
        switch link {
        case .openRecipe(let recipeId):
            selectedTab = .recipes
            recipesPath = NavigationPath()
            if syncService.collectionEntries.contains(where: { $0.id == recipeId && !$0.deleted }) {
                pendingSpotlightRecipeId = nil
                openRecipeDetail(recipeId: recipeId)
            } else {
                pendingSpotlightRecipeId = recipeId
            }
            deepLinkRouter.clear()
        case .addToShopping(let recipeId):
            Task { @MainActor in
                do {
                    let added = try await syncService.addWholeRecipeToShoppingList(recipeId: recipeId)
                    if added > 0 {
                        ShoppingFeedback.postStatus(ShoppingAddFeedback.message(for: added))
                    } else {
                        ShoppingFeedback.postStatus(String(localized: "shopping.no-items-to-add"))
                    }
                } catch {
                    ShoppingFeedback.postStatus(UserFacingAPIError.message(for: error))
                }
            }
            deepLinkRouter.clear()
        case .openShoppingList:
            selectedTab = .shopping
            shoppingPath = NavigationPath()
            deepLinkRouter.clear()
        case .openHome:
            selectedTab = .recipes
            recipesPath = NavigationPath()
            deepLinkRouter.clear()
        case .openPublicProfile(let username):
            selectedTab = .discover
            discoverListState?.clearAll()
            discoverPath = NavigationPath()
            discoverPath.append(DiscoverRoute.profile(username))
            deepLinkRouter.clear()
        case .openPublicRecipe(let recipeId, let username):
            selectedTab = .discover
            discoverListState?.clearAll()
            discoverPath = NavigationPath()
            discoverPath.append(DiscoverRoute.profile(username))
            discoverPath.append(
                DiscoverRoute.recipe(
                    id: recipeId,
                    allowDownloads: true,
                    imageSource: .publicRecipe
                )
            )
            deepLinkRouter.clear()
        case .openDiscover:
            selectedTab = .discover
            discoverListState?.clearAll()
            discoverPath = NavigationPath()
            deepLinkRouter.clear()
        case .openDiscoverCollection(let slug):
            selectedTab = .discover
            discoverListState?.clearAll()
            discoverPath = NavigationPath()
            discoverPath.append(DiscoverRoute.collection(slug))
            deepLinkRouter.clear()
        case .openDiscoverRecipe(let recipeId):
            selectedTab = .discover
            discoverListState?.clearAll()
            discoverPath = NavigationPath()
            discoverPath.append(
                DiscoverRoute.recipe(
                    id: recipeId,
                    allowDownloads: true,
                    imageSource: .curatedDiscover
                )
            )
            deepLinkRouter.clear()
        case .openRecipeFile(let url):
            // Spec 057 — silent import path. ImportRecipeSheet is NOT
            // presented; the coordinator runs `RecipeFileImportCoordinator`
            // directly and reports back via toast + navigation.
            guard let fileImportCoordinator else {
                AppLog.notice(.app, "open_recipe_file_without_coordinator")
                deepLinkRouter.clear()
                return
            }
            Task { @MainActor in
                let message = await fileImportCoordinator.importFile(
                    at: url,
                    isOnline: syncService.connectionState.isConnected
                )
                if let message {
                    pendingFileImportToast = message
                }
            }
            deepLinkRouter.clear()
        }
    }

    /// Navigate to a Spotlight/deep-link recipe once it appears in the loaded collection.
    func resolvePendingSpotlightRecipe(in entries: [CollectionEntry]) {
        guard let pendingId = pendingSpotlightRecipeId else { return }
        guard entries.contains(where: { $0.id == pendingId && !$0.deleted }) else { return }
        pendingSpotlightRecipeId = nil
        selectedTab = .recipes
        openRecipeDetail(recipeId: pendingId)
    }

    // MARK: - DEBUG

    #if DEBUG
    func openDebugTabIfNeeded(_ tab: AppTab?) {
        if let slug = DebugLaunchOptions.openDiscoverCollectionSlug, !slug.isEmpty {
            selectedTab = .discover
            discoverPath = NavigationPath()
            discoverPath.append(DiscoverRoute.collection(slug))
            return
        }
        if let username = DebugLaunchOptions.openDiscoverProfileUsername, !username.isEmpty {
            selectedTab = .discover
            discoverPath = NavigationPath()
            discoverPath.append(DiscoverRoute.profile(username))
            return
        }
        guard let tab else { return }
        if tab == .importTab {
            selectedTab = .recipes
            presentImport()
        } else {
            selectedTab = tab
        }
    }
    #endif

    /// Clears tab stacks, import sheet, and queued deep links after logout or account switch.
    func resetShellStateForLogout() {
        importPresentation = nil
        pendingSpotlightRecipeId = nil
        pendingRemindersSetup = false
        discoverListState?.clearAll()
        selectedTab = .recipes
        recipesPath = NavigationPath()
        discoverPath = NavigationPath()
        shoppingPath = NavigationPath()
        deepLinkRouter.clear()
        UserDefaults.standard.removeObject(forKey: DeepLinkRouter.pendingRecipeIdKey)
        AppGroup.userDefaults?.removeObject(forKey: DeepLinkRouter.pendingRecipeIdKey)
    }

    // MARK: - Private

    private func resetNestedNavigation(for tab: AppTab) {
        switch tab {
        case .discover:
            if !discoverPath.isEmpty {
                discoverPath = NavigationPath()
                discoverListState?.clearAll()
            }
        case .recipes:
            if !recipesPath.isEmpty {
                recipesPath = NavigationPath()
            } else if usesRegularRecipeSplit, wideRecipesState.selectedRecipeId != nil {
                wideRecipesState.selectedRecipeId = nil
            }
        case .shopping:
            if !shoppingPath.isEmpty { shoppingPath = NavigationPath() }
        default:
            break
        }
    }
}
