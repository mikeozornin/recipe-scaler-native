//
//  AppShellCoordinatorTests.swift
//
//  MIK-201 — tab routing and deep-link orchestration extracted from AppShellView.
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class AppShellCoordinatorTests: XCTestCase {

    private func makeCoordinator() throws -> (AppShellCoordinator, DeepLinkRouter, YjsSyncService) {
        let store = try YDocStore.inMemory()
        let sync = YjsSyncService(store: store)
        let router = DeepLinkRouter()
        let coordinator = AppShellCoordinator(syncService: sync, deepLinkRouter: router)
        return (coordinator, router, sync)
    }

    func test_importTabTap_setsPresentationWithoutChangingTab() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .recipes

        coordinator.handleTabSelection(.importTab)

        XCTAssertNotNil(coordinator.importPresentation)
        XCTAssertEqual(coordinator.selectedTab, .recipes)
    }

    func test_doubleImportTap_refreshesPresentationId() throws {
        let (coordinator, _, _) = try makeCoordinator()

        coordinator.handleTabSelection(.importTab)
        let firstId = coordinator.importPresentation?.id

        coordinator.handleTabSelection(.importTab)
        let secondId = coordinator.importPresentation?.id

        XCTAssertNotNil(firstId)
        XCTAssertNotNil(secondId)
        XCTAssertNotEqual(firstId, secondId)
    }

    func test_openShoppingList_switchesTabAndClearsRouter() throws {
        let (coordinator, router, _) = try makeCoordinator()
        router.handle(.openShoppingList)

        coordinator.handleDeepLink(.openShoppingList)

        XCTAssertEqual(coordinator.selectedTab, .shopping)
        XCTAssertNil(router.pending)
    }

    func test_openHome_switchesToRecipesAndClearsRouter() throws {
        let (coordinator, router, _) = try makeCoordinator()
        coordinator.selectedTab = .shopping
        router.handle(.openHome)

        coordinator.handleDeepLink(.openHome)

        XCTAssertEqual(coordinator.selectedTab, .recipes)
        XCTAssertNil(router.pending)
    }

    func test_openRecipe_whenMissing_stashesSpotlightId() throws {
        let (coordinator, router, _) = try makeCoordinator()
        let recipeId = "11111111-2222-3333-4444-555555555555"

        coordinator.handleDeepLink(.openRecipe(recipeId: recipeId))

        XCTAssertEqual(coordinator.pendingSpotlightRecipeId, recipeId)
        XCTAssertEqual(coordinator.selectedTab, .recipes)
        XCTAssertTrue(coordinator.recipesPath.isEmpty)
        XCTAssertNil(router.pending)
    }

    func test_resolvePendingSpotlightRecipe_navigatesWhenEntryAppears() throws {
        let (coordinator, _, _) = try makeCoordinator()
        let recipeId = "11111111-2222-3333-4444-555555555555"
        coordinator.handleDeepLink(.openRecipe(recipeId: recipeId))

        let entry = CollectionEntry(
            id: recipeId,
            name: "Test",
            color: "#3b82f6",
            imageUrl: nil,
            updatedAt: "2026-06-01T10:00:00Z",
            deleted: false,
            isPinned: false
        )
        coordinator.resolvePendingSpotlightRecipe(in: [entry])

        XCTAssertNil(coordinator.pendingSpotlightRecipeId)
        XCTAssertEqual(coordinator.selectedTab, .recipes)
        XCTAssertFalse(coordinator.recipesPath.isEmpty)
    }

    func test_completeImport_dismissesSheetAndNavigatesToSingleRecipe() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.importPresentation = ImportPresentation()
        coordinator.selectedTab = .discover

        let recipeId = "11111111-2222-3333-4444-555555555555"
        let message = coordinator.completeImport(
            ImportRecipesResult(recipeIds: [recipeId], importedCount: 1)
        )

        XCTAssertNil(coordinator.importPresentation)
        XCTAssertEqual(coordinator.selectedTab, .recipes)
        XCTAssertFalse(coordinator.recipesPath.isEmpty)
        XCTAssertNotNil(message)
    }

    func test_reTapCurrentTab_resetsNestedNavigation() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .recipes
        coordinator.recipesPath.append(RecipesRoute.folder(CollectionVirtualFolders.allRecipesFolderId))

        coordinator.handleTabSelection(.recipes)

        XCTAssertTrue(coordinator.recipesPath.isEmpty)
    }

    func test_resetShellStateForLogout_clearsPathsAndImport() throws {
        let (coordinator, router, _) = try makeCoordinator()
        coordinator.selectedTab = .shopping
        coordinator.importPresentation = ImportPresentation()
        coordinator.recipesPath.append(RecipesRoute.folder(CollectionVirtualFolders.allRecipesFolderId))
        coordinator.shoppingPath.append("shopping-depth-probe")
        coordinator.requestRemindersSetup()
        router.handle(.openRecipe(recipeId: "11111111-2222-3333-4444-555555555555"))
        UserDefaults.standard.set("legacy-recipe", forKey: DeepLinkRouter.pendingRecipeIdKey)

        coordinator.resetShellStateForLogout()

        XCTAssertEqual(coordinator.selectedTab, .recipes)
        XCTAssertNil(coordinator.importPresentation)
        XCTAssertTrue(coordinator.recipesPath.isEmpty)
        XCTAssertTrue(coordinator.shoppingPath.isEmpty)
        XCTAssertTrue(coordinator.discoverPath.isEmpty)
        XCTAssertFalse(coordinator.pendingRemindersSetup)
        XCTAssertNil(router.pending)
        XCTAssertNil(UserDefaults.standard.string(forKey: DeepLinkRouter.pendingRecipeIdKey))
    }

    func test_requestRemindersSetup_switchesToProfileAndSetsPending() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .shopping

        coordinator.requestRemindersSetup()

        XCTAssertEqual(coordinator.selectedTab, .profile)
        XCTAssertTrue(coordinator.pendingRemindersSetup)

        coordinator.clearPendingRemindersSetup()
        XCTAssertFalse(coordinator.pendingRemindersSetup)
    }
}
