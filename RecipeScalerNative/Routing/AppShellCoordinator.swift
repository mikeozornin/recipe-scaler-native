//
//  AppShellCoordinator.swift
//  RecipeScalerNative
//
//  Tab routing, deep-link orchestration, and modal presentation state for the app shell.
//

import SwiftUI

struct ImportPresentation: Identifiable {
    let id = UUID()
}

@MainActor
@Observable
final class AppShellCoordinator {
    private let syncService: YjsSyncService
    private let deepLinkRouter: DeepLinkRouter

    var selectedTab: AppTab = .recipes
    var importPresentation: ImportPresentation?
    var recipesPath = NavigationPath()
    var discoverPath = NavigationPath()
    var shoppingPath = NavigationPath()
    private(set) var pendingSpotlightRecipeId: String?

    init(syncService: YjsSyncService, deepLinkRouter: DeepLinkRouter) {
        self.syncService = syncService
        self.deepLinkRouter = deepLinkRouter
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

    func presentImport() {
        importPresentation = ImportPresentation()
    }

    // MARK: - Import completion

    /// Dismisses the import sheet, switches to Recipes, and optionally navigates to the imported recipe.
    /// Returns a localized toast message when import succeeded, otherwise `nil`.
    func completeImport(_ result: ImportRecipesResult) -> String? {
        importPresentation = nil
        selectedTab = .recipes
        if let id = result.primaryRecipeId {
            recipesPath.append(RecipesRoute.recipe(recipeId: id, folderContext: nil))
        }
        guard result.importedCount > 0 else { return nil }
        return Bundle.appPluralizedString(key: "import.success", count: result.importedCount)
    }

    // MARK: - Legacy deep link (UserDefaults from Share/Action extensions)

    func consumePendingRecipeIdIfNeeded() {
        guard let id = DeepLinkRouter.consumePendingRecipeId() else { return }
        selectedTab = .recipes
        recipesPath.append(RecipesRoute.recipe(recipeId: id, folderContext: nil))
    }

    // MARK: - Deep linking (Spotlight, URL scheme, Universal Links)

    func handleDeepLink(_ link: DeepLink) {
        switch link {
        case .openRecipe(let recipeId):
            selectedTab = .recipes
            if syncService.collectionEntries.contains(where: { $0.id == recipeId && !$0.deleted }) {
                pendingSpotlightRecipeId = nil
                recipesPath.append(RecipesRoute.recipe(recipeId: recipeId, folderContext: nil))
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
            deepLinkRouter.clear()
        case .openHome:
            selectedTab = .recipes
            deepLinkRouter.clear()
        }
    }

    /// Navigate to a Spotlight/deep-link recipe once it appears in the loaded collection.
    func resolvePendingSpotlightRecipe(in entries: [CollectionEntry]) {
        guard let pendingId = pendingSpotlightRecipeId else { return }
        guard entries.contains(where: { $0.id == pendingId && !$0.deleted }) else { return }
        pendingSpotlightRecipeId = nil
        selectedTab = .recipes
        recipesPath.append(RecipesRoute.recipe(recipeId: pendingId, folderContext: nil))
    }

    // MARK: - DEBUG

    #if DEBUG
    func openDebugTabIfNeeded(_ tab: AppTab?) {
        guard let tab else { return }
        if tab == .importTab {
            selectedTab = .recipes
            presentImport()
        } else {
            selectedTab = tab
        }
    }
    #endif

    // MARK: - Private

    private func resetNestedNavigation(for tab: AppTab) {
        switch tab {
        case .discover:
            if !discoverPath.isEmpty { discoverPath = NavigationPath() }
        case .recipes:
            if !recipesPath.isEmpty { recipesPath = NavigationPath() }
        case .shopping:
            if !shoppingPath.isEmpty { shoppingPath = NavigationPath() }
        default:
            break
        }
    }
}
