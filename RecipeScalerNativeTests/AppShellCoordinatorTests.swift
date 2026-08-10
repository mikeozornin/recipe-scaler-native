//
//  AppShellCoordinatorTests.swift
//
//  MIK-201 — tab routing and deep-link orchestration extracted from AppShellView.
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class AppShellCoordinatorTests: XCTestCase {

    private func makeCoordinator(
        discoverListState: DiscoverListStateStore? = nil
    ) throws -> (AppShellCoordinator, DeepLinkRouter, YjsSyncService) {
        let store = try YDocStore.inMemory()
        let sync = YjsSyncService.makeForTesting(store: store)
        let router = DeepLinkRouter()
        let coordinator = AppShellCoordinator(
            syncService: sync,
            deepLinkRouter: router,
            discoverListState: discoverListState
        )
        return (coordinator, router, sync)
    }

    func test_importTabTap_setsPresentationWithoutChangingTab() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .recipes

        coordinator.handleTabSelection(.importTab)

        XCTAssertNotNil(coordinator.importPresentation)
        XCTAssertEqual(coordinator.selectedTab, .recipes)
    }

    func test_wideSplit_openRecipeDetail_setsSelectedIdWithoutPath() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.usesRegularRecipeSplit = true
        let recipeId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

        coordinator.openRecipeDetail(recipeId: recipeId)

        XCTAssertEqual(coordinator.wideRecipesState.selectedRecipeId, recipeId)
        XCTAssertTrue(coordinator.recipesPath.isEmpty)
        XCTAssertEqual(coordinator.selectedTab, .recipes)
    }

    func test_regularLayoutTransition_preservesRecipeAndFolderAcrossModes() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        let syncIdentity = ObjectIdentifier(sync)
        let recipeId = "11111111-2222-3333-4444-555555555555"
        let folderId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let entry = CollectionEntry(
            id: recipeId,
            name: "Test",
            color: "#3b82f6",
            imageUrl: nil,
            updatedAt: "2026-06-01T10:00:00Z",
            deleted: false,
            isPinned: false,
            folderIds: [folderId]
        )

        coordinator.noteCompactFolderSelection(folderId)
        coordinator.noteCompactRecipeSelection(recipeId, folderContext: folderId)
        coordinator.setRegularLayout(true, entries: [entry])

        XCTAssertTrue(coordinator.usesRegularRecipeSplit)
        XCTAssertEqual(coordinator.wideRecipesState.selectedRecipeId, recipeId)
        XCTAssertEqual(coordinator.wideRecipesState.activeFolderId, folderId)
        // The folder remains drilled into the list column; the recipe itself
        // moves from the compact pushed detail into the regular detail column.
        XCTAssertEqual(coordinator.recipesPath.count, 1)

        coordinator.setRegularLayout(false, entries: [entry])

        XCTAssertFalse(coordinator.usesRegularRecipeSplit)
        XCTAssertEqual(coordinator.recipesPath.count, 2)
        XCTAssertEqual(
            ObjectIdentifier(sync),
            syncIdentity,
            "Layout transitions must keep the injected sync service identity"
        )
    }

    func test_wideSplit_autoSelectsFirstRecipeWithinActiveFolder() throws {
        let (coordinator, _, _) = try makeCoordinator()
        let folderId = "folder-a"
        let outside = CollectionEntry(
            id: "outside",
            name: "A outside",
            color: "#000000",
            imageUrl: nil,
            updatedAt: "2026-06-01T10:00:00Z",
            deleted: false,
            isPinned: false,
            folderIds: ["folder-b"]
        )
        let inside = CollectionEntry(
            id: "inside",
            name: "B inside",
            color: "#000000",
            imageUrl: nil,
            updatedAt: "2026-06-01T10:00:00Z",
            deleted: false,
            isPinned: false,
            folderIds: [folderId]
        )

        coordinator.usesRegularRecipeSplit = true
        coordinator.openFolderInWideSplit(folderId)
        coordinator.autoSelectFirstRecipeInWideSplitIfNeeded(entries: [outside, inside])

        XCTAssertEqual(coordinator.wideRecipesState.activeFolderId, folderId)
        XCTAssertEqual(coordinator.wideRecipesState.selectedRecipeId, inside.id)
    }

    func test_regularLayout_restoresPersistedVirtualFolderRoute() throws {
        let key = "layout.last-recipes-route"
        let prior = UserDefaults.standard.object(forKey: key)
        defer {
            if let prior {
                UserDefaults.standard.set(prior, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.set("/folder/all", forKey: key)
        let (coordinator, _, _) = try makeCoordinator()
        let entry = CollectionEntry(
            id: "recipe-1",
            name: "Recipe",
            color: "#000000",
            imageUrl: nil,
            updatedAt: "2026-06-01T10:00:00Z",
            deleted: false,
            isPinned: false
        )

        coordinator.setRegularLayout(true, entries: [entry])

        XCTAssertEqual(coordinator.wideRecipesState.activeFolderId, CollectionVirtualFolders.allRecipesFolderId)
        XCTAssertEqual(coordinator.wideRecipesState.selectedRecipeId, entry.id)
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
        coordinator.shoppingPath.append("shopping-depth-probe")
        router.handle(.openShoppingList)

        coordinator.handleDeepLink(.openShoppingList)

        XCTAssertEqual(coordinator.selectedTab, .shopping)
        XCTAssertTrue(coordinator.shoppingPath.isEmpty)
        XCTAssertNil(router.pending)
    }

    func test_openHome_switchesToRecipesAndClearsRouter() throws {
        let (coordinator, router, _) = try makeCoordinator()
        coordinator.selectedTab = .shopping
        coordinator.recipesPath.append(RecipesRoute.folder(CollectionVirtualFolders.allRecipesFolderId))
        router.handle(.openHome)

        coordinator.handleDeepLink(.openHome)

        XCTAssertEqual(coordinator.selectedTab, .recipes)
        XCTAssertTrue(coordinator.recipesPath.isEmpty)
        XCTAssertNil(router.pending)
    }

    /// Spec 059 — Universal Link public profile → Discover tab + profile route.
    func test_openPublicProfile_switchesToDiscover() throws {
        let (coordinator, router, _) = try makeCoordinator()
        coordinator.selectedTab = .recipes

        coordinator.handleDeepLink(.openPublicProfile(username: "alice"))

        XCTAssertEqual(coordinator.selectedTab, .discover)
        XCTAssertFalse(coordinator.discoverPath.isEmpty)
        XCTAssertNil(router.pending)
    }

    /// Spec 059 — Universal Link public recipe → Discover with profile + recipe stack.
    func test_openPublicRecipe_switchesToDiscoverWithStack() throws {
        let (coordinator, router, _) = try makeCoordinator()
        let recipeId = "11111111-2222-3333-4444-555555555555"

        coordinator.handleDeepLink(.openPublicRecipe(recipeId: recipeId, username: "alice"))

        XCTAssertEqual(coordinator.selectedTab, .discover)
        XCTAssertFalse(coordinator.discoverPath.isEmpty)
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

    /// Spec 057 T027 — `.openRecipeFile` runs the silent import path and
    /// MUST NOT open `ImportRecipeSheet`. The actual import is async and
    /// reads from disk; this test only checks the immediate observable
    /// state changes: sheet stays `nil`, deep link is cleared.
    func test_openRecipeFile_doesNotPresentImportSheet() throws {
        let (coordinator, router, _) = try makeCoordinator()

        // A non-existent file URL is fine — the coordinator kicks off a
        // Task that will fail later; we only assert on synchronous state.
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).recipe")
        coordinator.handleDeepLink(.openRecipeFile(url))

        XCTAssertNil(coordinator.importPresentation,
                     "AirDrop file import must not present ImportRecipeSheet")
        XCTAssertNil(router.pending,
                     "Deep link must be cleared even before the import Task finishes")
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

    func test_completeImport_inRegularSplit_selectsImportedRecipeWithoutPath() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.usesRegularRecipeSplit = true
        coordinator.importPresentation = ImportPresentation()

        let recipeId = "11111111-2222-3333-4444-555555555555"
        _ = coordinator.completeImport(
            ImportRecipesResult(recipeIds: [recipeId], importedCount: 1)
        )

        XCTAssertEqual(coordinator.wideRecipesState.selectedRecipeId, recipeId)
        XCTAssertTrue(coordinator.recipesPath.isEmpty)
    }

    func test_reTapCurrentTab_resetsNestedNavigation() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .recipes
        coordinator.recipesPath.append(RecipesRoute.folder(CollectionVirtualFolders.allRecipesFolderId))

        coordinator.handleTabSelection(.recipes)

        XCTAssertTrue(coordinator.recipesPath.isEmpty)
    }

    func test_reTapDiscoverClearsDiscoverListState() throws {
        let discoverListState = DiscoverListStateStore()
        discoverListState.recordAnchor(
            recipeID: "recipe-1",
            for: .collection("weeknight")
        )
        let (coordinator, _, _) = try makeCoordinator(discoverListState: discoverListState)
        coordinator.selectedTab = .discover
        coordinator.discoverPath.append(DiscoverRoute.collection("weeknight"))

        coordinator.handleTabSelection(.discover)

        XCTAssertTrue(coordinator.discoverPath.isEmpty)
        XCTAssertNil(discoverListState.anchor(for: .collection("weeknight")))
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
