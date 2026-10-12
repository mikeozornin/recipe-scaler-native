//
//  IPadShellItemTests.swift
//
//  Spec 081 (T012, plan.md Р2) — the iPad shell selection over the coordinator.
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class IPadShellItemTests: XCTestCase {

    private func makeCoordinator() throws -> AppShellCoordinator {
        let store = try YDocStore.inMemory()
        let sync = YjsSyncService.makeForTesting(store: store)
        return AppShellCoordinator(syncService: sync, deepLinkRouter: DeepLinkRouter())
    }

    private func selection(
        _ coordinator: AppShellCoordinator,
        sidebarShown: Bool = true,
        isSplitActive: Bool = false,
        firstRecipeIds: [String: String] = [:]
    ) -> IPadShellSelection {
        IPadShellSelection(
            coordinator: coordinator,
            sidebarShown: sidebarShown,
            isSplitActive: isSplitActive,
            collectionIds: ["f1", "f2"],
            firstRecipeId: { firstRecipeIds[$0] }
        )
    }

    func testProfileInRegularDoesNotChangeSelection() throws {
        let coordinator = try makeCoordinator()
        coordinator.selectedTab = .shopping
        var regular = selection(coordinator)
        regular.layoutMode = .padRegular

        regular.select(.tab(.profile))

        XCTAssertEqual(coordinator.selectedTab, .shopping)
        XCTAssertTrue(coordinator.isProfileSheetPresented)
        XCTAssertEqual(regular.item, .tab(.shopping))

        // Narrowed with the sheet up: «Профиль» keeps the sheet, no profile page.
        selection(coordinator).select(.tab(.profile))
        XCTAssertEqual(coordinator.selectedTab, .shopping)
        XCTAssertTrue(coordinator.isProfileSheetPresented)

        // Compact window: «Профиль» is a tab.
        coordinator.profileSheetDidDismiss()
        selection(coordinator).select(.tab(.profile))
        XCTAssertEqual(coordinator.selectedTab, .profile)
        XCTAssertFalse(coordinator.isProfileSheetPresented)
    }

    func testNewCollectionAsksForANameAndKeepsSelection() throws {
        let coordinator = try makeCoordinator()
        coordinator.selectedTab = .shopping
        var asked = 0
        var shell = selection(coordinator)
        shell.onNewCollection = { asked += 1 }

        shell.select(.newCollection)

        XCTAssertEqual(asked, 1)
        XCTAssertEqual(coordinator.selectedTab, .shopping)
        XCTAssertEqual(coordinator.recipesPath, [])
        XCTAssertEqual(shell.item, .tab(.shopping))
    }

    /// T017: the sidebar alert and the phone list share the commit; blank names never save.
    func testNewCollectionNameTrimsWhitespaceAndNewlines() {
        XCTAssertNil(NewCollectionCommit.name(from: ""))
        XCTAssertNil(NewCollectionCommit.name(from: "   "))
        XCTAssertNil(NewCollectionCommit.name(from: "\n\n"))
        XCTAssertNil(NewCollectionCommit.name(from: " \t\n "))
        XCTAssertEqual(NewCollectionCommit.name(from: "\n Супы \n"), "Супы")
        XCTAssertEqual(NewCollectionCommit.name(from: "Супы  дня"), "Супы  дня")
    }

    func testAssistantDoesNotChangeSelection() throws {
        let coordinator = try makeCoordinator()
        coordinator.selectedTab = .shopping
        selection(coordinator).select(.tab(.assistant))

        XCTAssertEqual(coordinator.selectedTab, .shopping)
        XCTAssertTrue(coordinator.pendingAssistantTabOpen)
        XCTAssertEqual(selection(coordinator).item, .tab(.shopping))

        coordinator.consumeAssistantTabOpen()
        coordinator.selectedTab = .recipes
        coordinator.recipesPath = [.folder("f1"), .recipe(recipeId: "r1", folderContext: "f1")]
        selection(coordinator).select(.tab(.assistant))

        XCTAssertTrue(coordinator.pendingAssistantTabOpen)
        XCTAssertEqual(coordinator.recipesPath, [.folder("f1"), .recipe(recipeId: "r1", folderContext: "f1")])
        XCTAssertEqual(selection(coordinator).item, .collection("f1"))
    }

    func testCollectionMapsToRecipesPath() throws {
        let coordinator = try makeCoordinator()
        coordinator.selectedTab = .discover

        // US1, compact, phone stack: the phone collection screen.
        selection(coordinator).select(.collection("f1"))
        XCTAssertEqual(coordinator.selectedTab, .recipes)
        XCTAssertEqual(coordinator.recipesPath, [.folder("f1")])
        XCTAssertEqual(selection(coordinator).item, .collection("f1"))

        // Split active: the collection and its first recipe.
        let split = selection(coordinator, isSplitActive: true, firstRecipeIds: ["f2": "r9"])
        split.select(.collection("f2"))
        XCTAssertEqual(coordinator.recipesPath, [.folder("f2"), .recipe(recipeId: "r9", folderContext: "f2")])

        // Split active, empty collection.
        split.select(.collection("f1"))
        XCTAssertEqual(coordinator.recipesPath, [.folder("f1")])

        // «Рецепты» while a collection is selected: all recipes.
        selection(coordinator).select(.tab(.recipes))
        XCTAssertEqual(coordinator.selectedTab, .recipes)
        XCTAssertEqual(coordinator.recipesPath, [])
        XCTAssertEqual(selection(coordinator).item, .tab(.recipes))
    }

    /// A path written elsewhere (iPhone stack, deep link, restored size class) selects
    /// the sidebar row of its user collection.
    func testDeepLinkPathMapsToCollection() throws {
        let coordinator = try makeCoordinator()
        coordinator.selectedTab = .recipes
        coordinator.recipesPath = [.folder("f2"), .recipe(recipeId: "r1", folderContext: "f2")]
        XCTAssertEqual(selection(coordinator).item, .collection("f2"))

        coordinator.recipesPath = [.folder(CollectionVirtualFolders.allRecipesFolderId)]
        XCTAssertEqual(selection(coordinator).item, .tab(.recipes))

        coordinator.recipesPath = [.folder("deleted")]
        XCTAssertEqual(selection(coordinator).item, .tab(.recipes))

        coordinator.recipesPath = [.recipe(recipeId: "r1", folderContext: nil)]
        XCTAssertEqual(selection(coordinator).item, .tab(.recipes))

        coordinator.recipesPath = [.folder("f1")]
        coordinator.selectedTab = .shopping
        XCTAssertEqual(selection(coordinator).item, .tab(.shopping))
    }

    func testCollectionInTopBarMapsToRecipesTab() throws {
        let coordinator = try makeCoordinator()
        selection(coordinator).select(.collection("f1"))

        let topBar = selection(coordinator, sidebarShown: false)
        XCTAssertEqual(topBar.item, .tab(.recipes))
        XCTAssertEqual(coordinator.recipesPath, [.folder("f1")])
        XCTAssertEqual(selection(coordinator).item, .collection("f1"))
    }
}
