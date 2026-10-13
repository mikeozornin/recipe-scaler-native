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

    /// Spec 074 — fake assistant tab: tap sets the pending-open flag and keeps
    /// the current selection (the sheet presents over whichever tab is active).
    func test_assistantTabTap_setsPendingFlagWithoutChangingTab() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .recipes

        coordinator.handleTabSelection(.assistant)

        XCTAssertTrue(coordinator.pendingAssistantTabOpen)
        XCTAssertEqual(coordinator.selectedTab, .recipes)
    }

    func test_assistantTabTap_keepsActiveTabAndFlags() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .discover

        coordinator.handleTabSelection(.assistant)

        XCTAssertTrue(coordinator.pendingAssistantTabOpen)
        XCTAssertEqual(coordinator.selectedTab, .discover)
    }

    /// Spec 074 — logout must clear the tab-entry flag together with the
    /// external request, so a queued open cannot leak into a fresh session.
    func test_resetShellStateForLogout_clearsAssistantTabFlag() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.handleTabSelection(.assistant)
        XCTAssertTrue(coordinator.pendingAssistantTabOpen)

        coordinator.resetShellStateForLogout()

        XCTAssertFalse(coordinator.pendingAssistantTabOpen)
    }

    /// Spec 081 (FR-021) — ✦ in an iPad toolbar opens like the tab; ✦ on «Покупки» and
    /// «Подборки» asks for a new chat. The flag goes with the open and with a logout.
    func test_assistantToolbarTap_carriesNewChatUntilConsumed() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .shopping

        coordinator.handleAssistantToolbarTap(startsNewChat: true)

        XCTAssertTrue(coordinator.pendingAssistantTabOpen)
        XCTAssertTrue(coordinator.pendingAssistantTabOpenStartsNewChat)
        XCTAssertEqual(coordinator.selectedTab, .shopping)

        coordinator.consumeAssistantTabOpen()
        XCTAssertFalse(coordinator.pendingAssistantTabOpen)
        XCTAssertFalse(coordinator.pendingAssistantTabOpenStartsNewChat)

        coordinator.handleAssistantToolbarTap(startsNewChat: true)
        coordinator.resetShellStateForLogout()
        XCTAssertFalse(coordinator.pendingAssistantTabOpenStartsNewChat)

        // The recipe ✦ and the tab keep the recent chat.
        coordinator.handleAssistantToolbarTap(startsNewChat: false)
        XCTAssertTrue(coordinator.pendingAssistantTabOpen)
        XCTAssertFalse(coordinator.pendingAssistantTabOpenStartsNewChat)
    }

    /// PI-5 race (spec 074 review): an external request can arrive in the same
    /// SwiftUI transaction as a tab tap. AppShellView's tab-open handler skips
    /// the manual open when a request was routed, so the coordinator contract
    /// here is: consuming the tab flag must not touch the queued request —
    /// the request stays queued until the sheet consumes it.
    func test_consumeAssistantTabOpen_keepsQueuedExternalRequest() throws {
        let (coordinator, _, _) = try makeCoordinator()

        coordinator.handleTabSelection(.assistant)
        XCTAssertTrue(coordinator.pendingAssistantTabOpen)
        coordinator.openAssistantWithMessage("Summarize recipe")

        coordinator.consumeAssistantTabOpen()

        XCTAssertFalse(coordinator.pendingAssistantTabOpen)
        XCTAssertNotNil(coordinator.pendingAssistantOpenRequest)
        XCTAssertEqual(coordinator.pendingAssistantOpenRequest?.message, "Summarize recipe")
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

    // MARK: - Spec 081 — profile sheet in a wide iPad window (T019a)

    func testWideningOnProfileTabRestoresPreviousAndPresentsSheet() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .shopping
        coordinator.selectedTab = .profile // compact window: the profile tab

        coordinator.normalizeProfileSelection(previous: coordinator.lastNonProfileTab, layoutMode: .padRegular)

        XCTAssertEqual(coordinator.selectedTab, .shopping)
        XCTAssertTrue(coordinator.isProfileSheetPresented)
    }

    func testNarrowingKeepsProfileSheet() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .discover
        coordinator.presentProfileSheet()

        coordinator.normalizeProfileSelection(previous: coordinator.lastNonProfileTab, layoutMode: .phone)

        XCTAssertEqual(coordinator.selectedTab, .discover)
        XCTAssertTrue(coordinator.isProfileSheetPresented)

        let revision = coordinator.profileSheetRevision
        coordinator.profileSheetDidDismiss()
        XCTAssertFalse(coordinator.isProfileSheetPresented)
        XCTAssertEqual(coordinator.profileSheetRevision, revision &+ 1)
    }

    /// The sheet was kept up on narrowing; the compact «Профиль» tab must not add a page.
    func testProfileTabAfterNarrowingKeepsSingleSheet() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .shopping
        coordinator.presentProfileSheet()

        coordinator.selectedTab = .profile
        // The shell's `onChange(of: selectedTab)` in the compact window.
        coordinator.normalizeProfileSelection(previous: .shopping, layoutMode: .phone)

        XCTAssertEqual(coordinator.selectedTab, .shopping)
        XCTAssertTrue(coordinator.isProfileSheetPresented)

        // Sheet closed: the compact «Профиль» is a tab again.
        coordinator.profileSheetDidDismiss()
        coordinator.selectedTab = .profile
        coordinator.normalizeProfileSelection(previous: .shopping, layoutMode: .phone)
        XCTAssertEqual(coordinator.selectedTab, .profile)
        XCTAssertFalse(coordinator.isProfileSheetPresented)
    }

    func testRemindersSetupInRegularPresentsSheet() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .shopping

        coordinator.requestRemindersSetup()
        // The shell's `onChange(of: selectedTab)` with the old value.
        coordinator.normalizeProfileSelection(previous: .shopping, layoutMode: .padRegular)

        XCTAssertEqual(coordinator.selectedTab, .shopping)
        XCTAssertTrue(coordinator.isProfileSheetPresented)
        XCTAssertTrue(coordinator.pendingRemindersSetup, "the sheet consumes it on appear")
    }

    func testLogoutDismissesProfileSheet() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .shopping
        coordinator.presentProfileSheet()

        coordinator.resetShellStateForLogout()

        XCTAssertFalse(coordinator.isProfileSheetPresented)
        XCTAssertEqual(coordinator.selectedTab, .recipes)
        XCTAssertEqual(coordinator.lastNonProfileTab, .recipes)
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

    func test_openAssistantWithMessage_trimsAndQueuesRequest() throws {
        let (coordinator, _, _) = try makeCoordinator()

        coordinator.openAssistantWithMessage("  Собери корзину  \n")

        XCTAssertEqual(coordinator.pendingAssistantOpenRequest?.requestId, 1)
        XCTAssertEqual(coordinator.pendingAssistantOpenRequest?.message, "Собери корзину")
    }

    func test_openAssistantWithMessage_ignoresBlankMessage() throws {
        let (coordinator, _, _) = try makeCoordinator()

        coordinator.openAssistantWithMessage(" \n\t ")

        XCTAssertNil(coordinator.pendingAssistantOpenRequest)
    }

    func test_openAssistantWithMessage_usesDistinctIdsForRepeatedPrompt() throws {
        let (coordinator, _, _) = try makeCoordinator()

        coordinator.openAssistantWithMessage("Собери корзину")
        let first = coordinator.pendingAssistantOpenRequest
        coordinator.openAssistantWithMessage("Собери корзину")
        let second = coordinator.pendingAssistantOpenRequest

        XCTAssertEqual(first?.message, second?.message)
        XCTAssertNotEqual(first?.requestId, second?.requestId)
    }

    func test_consumeAssistantOpenRequest_doesNotDropNewerRequest() throws {
        let (coordinator, _, _) = try makeCoordinator()

        coordinator.openAssistantWithMessage("first")
        let first = try XCTUnwrap(coordinator.pendingAssistantOpenRequest)
        coordinator.openAssistantWithMessage("second")

        coordinator.consumeAssistantOpenRequest(first)

        XCTAssertEqual(coordinator.pendingAssistantOpenRequest?.message, "second")
    }

    /// Review finding: logout must invalidate pending assistant state so an
    /// open sheet can detect the session change (assistantSessionEpoch) and no
    /// stale external request survives into the fresh session.
    func test_resetShellStateForLogout_bumpsAssistantSessionEpochAndClearsPendingRequest() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.openAssistantWithMessage("Собери корзину")
        let epochBefore = coordinator.assistantSessionEpoch

        coordinator.resetShellStateForLogout()

        XCTAssertEqual(
            coordinator.assistantSessionEpoch,
            epochBefore + 1,
            "Logout must bump the assistant epoch so an open sheet tears down"
        )
        XCTAssertNil(coordinator.pendingAssistantOpenRequest)
    }

    // MARK: - Spec 081 — «Развернуть» and the sidebar (T024)

    func testExpandHidesSidebarBesideContentAndCollapseBringsItBack() throws {
        let (coordinator, _, _) = try makeCoordinator()
        let sidebar = FakeIPadSidebar(shown: true)
        coordinator.iPadSidebar = sidebar

        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)
        XCTAssertTrue(coordinator.recipeDetailExpanded)
        XCTAssertFalse(sidebar.isSidebarShown)
        XCTAssertTrue(coordinator.sidebarHiddenByRecipeExpand)

        coordinator.setRecipeDetailExpanded(false, isPadRegular: true)
        XCTAssertFalse(coordinator.recipeDetailExpanded)
        XCTAssertTrue(sidebar.isSidebarShown)
        XCTAssertFalse(coordinator.sidebarHiddenByRecipeExpand)
    }

    func testFloatingSidebarIsClosedAndNotBroughtBack() throws {
        let (coordinator, _, _) = try makeCoordinator()
        let sidebar = FakeIPadSidebar(shown: true, overlays: true)
        coordinator.iPadSidebar = sidebar

        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)
        coordinator.setRecipeDetailExpanded(false, isPadRegular: true)

        XCTAssertFalse(sidebar.isSidebarShown)
        XCTAssertEqual(sidebar.calls, [true])
    }

    /// The user shows the sidebar again while expanded: «Свернуть» leaves it alone.
    func testCollapseDoesNotFightASidebarTheUserShowed() throws {
        let (coordinator, _, _) = try makeCoordinator()
        let sidebar = FakeIPadSidebar(shown: true)
        coordinator.iPadSidebar = sidebar
        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)

        sidebar.isSidebarShown = true
        coordinator.noteSidebarShown(true)
        XCTAssertFalse(coordinator.sidebarHiddenByRecipeExpand)
        // … and hides it again: still the user's choice.
        sidebar.isSidebarShown = false
        coordinator.noteSidebarShown(false)

        coordinator.setRecipeDetailExpanded(false, isPadRegular: true)
        XCTAssertFalse(sidebar.isSidebarShown)
        XCTAssertEqual(sidebar.calls, [true])
    }

    /// A compact window (or one too narrow for the split) collapses the recipe; the sidebar
    /// waits for the wide window and comes back there.
    func testCompactCollapsesAndTheSidebarWaitsForTheWideWindow() throws {
        let (coordinator, _, _) = try makeCoordinator()
        let sidebar = FakeIPadSidebar(shown: true)
        coordinator.iPadSidebar = sidebar
        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)

        coordinator.setRecipeDetailExpanded(false, isPadRegular: false)
        XCTAssertFalse(coordinator.recipeDetailExpanded, "Widening must not bring the expanded recipe back")
        XCTAssertFalse(sidebar.isSidebarShown)
        XCTAssertTrue(coordinator.sidebarHiddenByRecipeExpand)

        coordinator.restoreSidebarHiddenByRecipeExpand(isPadRegular: true)
        XCTAssertTrue(sidebar.isSidebarShown)
        XCTAssertFalse(coordinator.sidebarHiddenByRecipeExpand)
    }

    /// Collapsed while the user is on another tab: the sidebar does not pop open there,
    /// it comes back with the return to Recipes.
    func testCollapseOffRecipesDefersTheSidebarToTheReturn() throws {
        let (coordinator, _, _) = try makeCoordinator()
        let sidebar = FakeIPadSidebar(shown: true)
        coordinator.iPadSidebar = sidebar
        coordinator.selectedTab = .recipes
        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)
        coordinator.selectedTab = .shopping

        coordinator.setRecipeDetailExpanded(false, isPadRegular: true)
        XCTAssertFalse(sidebar.isSidebarShown)
        coordinator.restoreSidebarHiddenByRecipeExpand(isPadRegular: true)
        XCTAssertFalse(sidebar.isSidebarShown, "Still on «Покупки»")

        coordinator.selectedTab = .recipes
        coordinator.restoreSidebarHiddenByRecipeExpand(isPadRegular: true)
        XCTAssertTrue(sidebar.isSidebarShown)
    }

    func testLogoutBringsBackASidebarHiddenByExpand() throws {
        let (coordinator, _, _) = try makeCoordinator()
        let sidebar = FakeIPadSidebar(shown: true)
        coordinator.iPadSidebar = sidebar
        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)
        coordinator.selectedTab = .shopping

        coordinator.resetShellStateForLogout()

        XCTAssertTrue(sidebar.isSidebarShown)
        XCTAssertFalse(coordinator.recipeDetailExpanded)
        XCTAssertFalse(coordinator.sidebarHiddenByRecipeExpand)
    }

    // MARK: - Spec 081 — recipe edit on the iPad (US5)

    private func makeEditSession(
        _ sync: YjsSyncService,
        recipeId: String = "r1",
        owner: UUID = UUID()
    ) -> IPadRecipeEditSession {
        IPadRecipeEditSession(
            recipeId: recipeId,
            viewModel: RecipeEditViewModel(recipe: makeEditableRecipe(id: recipeId), syncService: sync),
            owner: owner
        )
    }

    /// T041/T043: edit expands like «Развернуть»; «Готово» keeps the recipe expanded and
    /// the sidebar hidden; «Свернуть» brings it back (`#recipes/focus`).
    func testEditExpandsAndAfterDoneTheSidebarWaitsForCollapse() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        let sidebar = FakeIPadSidebar(shown: true)
        coordinator.iPadSidebar = sidebar
        coordinator.selectedTab = .recipes

        coordinator.beginRecipeEdit(makeEditSession(sync))
        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)
        XCTAssertFalse(sidebar.isSidebarShown)

        coordinator.endRecipeEdit(recipeId: "r1", isPadRegular: true)
        XCTAssertNil(coordinator.recipeEdit)
        XCTAssertTrue(coordinator.recipeDetailExpanded, "«Готово» keeps the recipe expanded")
        XCTAssertFalse(sidebar.isSidebarShown)

        coordinator.setRecipeDetailExpanded(false, isPadRegular: true)
        XCTAssertTrue(sidebar.isSidebarShown)
        XCTAssertEqual(sidebar.calls, [true, false])
    }

    /// T043: an edit through a compact window. The compact window collapses the recipe; back
    /// in the wide one the sidebar is not brought back while the edit goes on, the edit
    /// expands again and «Свернуть» after «Готово» restores the sidebar once.
    func testEditThroughACompactWindowKeepsTheSidebarForTheCollapse() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        let sidebar = FakeIPadSidebar(shown: true)
        coordinator.iPadSidebar = sidebar
        coordinator.selectedTab = .recipes
        coordinator.recipesPath = [recipeRoute("r1")]
        coordinator.beginRecipeEdit(makeEditSession(sync))
        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)

        coordinator.setRecipeDetailExpanded(false, isPadRegular: false)
        coordinator.restoreSidebarHiddenByRecipeExpand(isPadRegular: true)
        XCTAssertFalse(sidebar.isSidebarShown, "No flash of the sidebar before the edit expands again")
        XCTAssertTrue(coordinator.sidebarHiddenByRecipeExpand)

        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)
        XCTAssertTrue(coordinator.sidebarHiddenByRecipeExpand)
        coordinator.endRecipeEdit(recipeId: "r1", isPadRegular: true)
        coordinator.setRecipeDetailExpanded(false, isPadRegular: true)
        XCTAssertTrue(sidebar.isSidebarShown)
        XCTAssertEqual(sidebar.calls, [true, false])
    }

    /// «Готово» in a compact window: the sidebar waits for the wide window, as after «Свернуть».
    func testDoneInACompactWindowDefersTheSidebar() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        let sidebar = FakeIPadSidebar(shown: true)
        coordinator.iPadSidebar = sidebar
        coordinator.selectedTab = .recipes
        coordinator.beginRecipeEdit(makeEditSession(sync))
        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)
        coordinator.setRecipeDetailExpanded(false, isPadRegular: false)

        coordinator.endRecipeEdit(recipeId: "r1", isPadRegular: false)
        XCTAssertFalse(sidebar.isSidebarShown)
        coordinator.restoreSidebarHiddenByRecipeExpand(isPadRegular: true)
        XCTAssertTrue(sidebar.isSidebarShown)
    }

    func testEndingAnotherRecipesEditKeepsTheSession() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        coordinator.beginRecipeEdit(makeEditSession(sync, recipeId: "r1"))

        coordinator.endRecipeEdit(recipeId: "r2", isPadRegular: true)
        XCTAssertEqual(coordinator.recipeEdit?.recipeId, "r1")
    }

    /// The user left the edit of r1 on another tab, and a deep link, an import or a
    /// deletion opened r2 meanwhile: the edit ends with no recipe view to end it, so the
    /// sidebar «Развернуть» hid comes back with «Свернуть».
    func testAnEditLeftOnAnotherTabEndsWhenAnotherRecipeOpens() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        let sidebar = FakeIPadSidebar(shown: true)
        coordinator.iPadSidebar = sidebar
        coordinator.selectedTab = .recipes
        coordinator.recipesPath = [recipeRoute("r1")]
        let view = UUID()
        let session = makeEditSession(sync, recipeId: "r1", owner: view)
        coordinator.beginRecipeEdit(session)
        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)
        XCTAssertFalse(sidebar.isSidebarShown)
        coordinator.selectedTab = .shopping
        session.release(owner: view)

        _ = coordinator.completeImport(ImportRecipesResult(recipeIds: ["r2"], importedCount: 1))
        XCTAssertNil(coordinator.recipeEdit, "The edit of r1 outlived its recipe")

        coordinator.setRecipeDetailExpanded(false, isPadRegular: true)
        XCTAssertTrue(sidebar.isSidebarShown, "The sidebar stayed hidden for an edit no one is in")
    }

    func testAnEditLeftOnAnotherTabEndsWhenItsRecipeCloses() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        coordinator.recipesPath = [recipeRoute("r1")]
        let view = UUID()
        let session = makeEditSession(sync, recipeId: "r1", owner: view)
        coordinator.beginRecipeEdit(session)
        session.release(owner: view)

        // A deep link to a recipe not loaded yet empties the path until it arrives.
        coordinator.handleDeepLink(.openRecipe(recipeId: "r2"))
        XCTAssertNil(coordinator.recipeEdit)
    }

    /// A path change that keeps r1 open (a collection picked around it) keeps the edit.
    func testAnEditLeftOnAnotherTabSurvivesWhileItsRecipeStaysOpen() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        coordinator.recipesPath = [recipeRoute("r1")]
        let view = UUID()
        let session = makeEditSession(sync, recipeId: "r1", owner: view)
        coordinator.beginRecipeEdit(session)
        session.release(owner: view)

        coordinator.recipesPath = [.folder(CollectionVirtualFolders.allRecipesFolderId), recipeRoute("r1")]
        XCTAssertTrue(coordinator.recipeEdit === session)
    }

    /// A layout change rebuilds the recipe view, and the reflow pops the new stack before
    /// the new view takes up the edit: the edit waits for the keeper to put the path back.
    func testTheReflowPopDoesNotEndAnEditBeingRebuilt() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        let kept = [recipeRoute("r1")]
        coordinator.recipesPath = kept
        let view = UUID()
        let session = makeEditSession(sync, recipeId: "r1", owner: view)
        coordinator.beginRecipeEdit(session)
        coordinator.noteRecipesStackRebuilt()
        session.release(owner: view)

        coordinator.recipesPath = []
        XCTAssertTrue(coordinator.recipeEdit === session, "The reflow's pop ended the edit")
        // The keeper puts the path back.
        coordinator.recipesPath = kept
        XCTAssertTrue(coordinator.recipeEdit === session)
    }

    /// A pop the keeper does not put back (here r1 is not in the collection) or a pop well
    /// after the layout change ends an edit no view is in.
    func testAnEditEndsWithAPopThatIsNotPutBack() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        let kept = [recipeRoute("r1")]
        coordinator.recipesPath = kept
        let view = UUID()
        coordinator.beginRecipeEdit(makeEditSession(sync, recipeId: "r1", owner: view))
        coordinator.recipeEdit?.release(owner: view)

        coordinator.noteRecipesStackRebuilt()
        coordinator.recipesPath = []
        XCTAssertNotNil(coordinator.recipeEdit)
        XCTAssertNil(coordinator.recipesStackPathToRestore(kept))
        XCTAssertNil(coordinator.recipeEdit, "Not put back")

        coordinator.recipesPath = kept
        coordinator.beginRecipeEdit(makeEditSession(sync, recipeId: "r1", owner: view))
        coordinator.recipeEdit?.release(owner: view)
        coordinator.noteRecipesStackRebuilt(at: Date().addingTimeInterval(-1))
        coordinator.recipesPath = []
        XCTAssertNil(coordinator.recipeEdit, "The user's own «Назад» later")
    }

    /// On screen the recipe view in the edit ends it as it leaves (`leaveIPadEditSession`);
    /// the path change alone does not, or a «Назад» mid-rebuild would drop the edit.
    func testAnEditWithItsViewOnScreenOutlivesThePathChange() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        coordinator.recipesPath = [recipeRoute("r1")]
        let session = makeEditSession(sync, recipeId: "r1")
        coordinator.beginRecipeEdit(session)

        coordinator.recipesPath = [recipeRoute("r2")]
        XCTAssertTrue(coordinator.recipeEdit === session)
    }

    /// «Свернуть» while the session still holds a recipe that is no longer open (its view
    /// has not left yet): only an edit of the open recipe keeps the sidebar hidden.
    func testCollapseIgnoresAnEditOfAnotherRecipe() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        let sidebar = FakeIPadSidebar(shown: true)
        coordinator.iPadSidebar = sidebar
        coordinator.selectedTab = .recipes
        coordinator.recipesPath = [recipeRoute("r1")]
        coordinator.beginRecipeEdit(makeEditSession(sync, recipeId: "r1"))
        coordinator.setRecipeDetailExpanded(true, isPadRegular: true)

        coordinator.recipesPath = [recipeRoute("r2")]
        coordinator.setRecipeDetailExpanded(false, isPadRegular: true)
        XCTAssertTrue(sidebar.isSidebarShown)
    }

    func testLogoutEndsTheEdit() throws {
        let (coordinator, _, sync) = try makeCoordinator()
        coordinator.beginRecipeEdit(makeEditSession(sync))
        coordinator.noteRecipeStartedInEdit("r1")

        coordinator.resetShellStateForLogout()

        XCTAssertNil(coordinator.recipeEdit)
        XCTAssertTrue(coordinator.recipeIdsStartedInEdit.isEmpty)
    }

    /// T043: the view being torn down loses focus; only the view editing now is heard.
    func testEditSessionHearsOnlyItsOwner() throws {
        let (_, _, sync) = try makeCoordinator()
        let first = UUID()
        let second = UUID()
        let session = makeEditSession(sync, owner: first)

        session.noteFocus(.title, owner: first)
        session.noteTitleText("Шарлотка с яблоками", owner: first)
        session.adopt(owner: second)
        session.noteBlur(.title, owner: first)
        session.noteTitleText("", owner: first)
        session.release(owner: first)
        XCTAssertEqual(session.focus, .title)
        XCTAssertEqual(session.titleDraft, "Шарлотка с яблоками")
        XCTAssertEqual(session.owner, second)

        session.noteFocus(.steps(from: 12, to: 12), owner: second)
        session.noteBlur(.title, owner: second)
        XCTAssertEqual(session.focus, .steps(from: 12, to: 12), "A title blur leaves the steps focus")
        XCTAssertNil(session.titleDraft, "The title is saved on its blur")

        session.noteBlur(.steps, owner: second)
        XCTAssertEqual(session.focus, IPadRecipeEditFocus.none)
        session.release(owner: second)
        XCTAssertNil(session.owner)
    }

    /// T043: a rebuild brings up several views of the recipe in turn. When a later one
    /// leaves, the edit goes back to the view still on screen, which keeps noting its focus.
    func testEditSessionGoesBackToTheViewStillInTheEdit() throws {
        let (_, _, sync) = try makeCoordinator()
        let onScreen = UUID()
        let passing = UUID()
        let lingering = UUID()
        let session = makeEditSession(sync, owner: onScreen)

        session.adopt(owner: lingering)
        session.adopt(owner: passing)
        session.release(owner: passing)
        XCTAssertEqual(session.owner, lingering)

        session.noteFocus(.steps(from: 6, to: 6), owner: onScreen)
        XCTAssertEqual(session.owner, onScreen, "The view the user types in edits now")
        XCTAssertEqual(session.focus, .steps(from: 6, to: 6))
        session.noteBlur(.steps, owner: lingering)
        session.noteFocus(.title, owner: passing)
        XCTAssertEqual(session.focus, .steps(from: 6, to: 6), "Views not editing now are not heard")

        session.release(owner: onScreen)
        XCTAssertEqual(session.owner, lingering)
        session.release(owner: lingering)
        XCTAssertNil(session.owner)
    }

    /// T043: which recipe views take up the edit. A view that has just left it with
    /// «Готово» (its view model, out of edit) does not take it up again on a recipe update
    /// before the session ends.
    func testEditSessionAdmitsOnlyAViewThatCanBeInIt() throws {
        let (_, _, sync) = try makeCoordinator()
        let session = makeEditSession(sync)
        let ownEdit = RecipeEditViewModel(recipe: makeEditableRecipe(id: "r1"), syncService: sync)

        XCTAssertTrue(session.admits(viewModel: nil, viewEditing: false), "A new view adopts")
        XCTAssertTrue(session.admits(viewModel: ownEdit, viewEditing: false), "A new view with its reading model adopts")
        XCTAssertTrue(session.admits(viewModel: session.viewModel, viewEditing: true), "Back from another tab")
        XCTAssertFalse(session.admits(viewModel: session.viewModel, viewEditing: false), "Just left with «Готово»")
        XCTAssertFalse(session.admits(viewModel: ownEdit, viewEditing: true), "An edit of its own")
    }

    // MARK: - Spec 081 — the recipes stack across a layout change (FR-018, T043)

    /// Only a layout change arms the put-back of the recipes stack, for the reflow's pop
    /// right after it, and once.
    func testRecipesStackIsPutBackOnceRightAfterALayoutChange() throws {
        let (coordinator, _, _) = try makeCoordinator()
        let kept: [RecipesRoute] = [.folder(CollectionVirtualFolders.allRecipesFolderId)]
        let rebuilt = Date()
        XCTAssertNil(coordinator.recipesStackPathToRestore(kept, at: rebuilt), "No layout change")

        coordinator.noteRecipesStackRebuilt(at: rebuilt)
        XCTAssertEqual(coordinator.recipesStackPathToRestore(kept, at: rebuilt.addingTimeInterval(0.15)), kept)
        XCTAssertNil(coordinator.recipesStackPathToRestore(kept, at: rebuilt.addingTimeInterval(0.2)), "Once")

        coordinator.noteRecipesStackRebuilt(at: rebuilt)
        XCTAssertNil(
            coordinator.recipesStackPathToRestore(kept, at: rebuilt.addingTimeInterval(0.8)),
            "The user's own «Назад»"
        )
    }

    /// The app emptying the path itself is not a reflow to undo.
    func testTheAppsOwnPathResetsCancelThePutBack() throws {
        let (coordinator, _, _) = try makeCoordinator()
        let kept: [RecipesRoute] = [.folder(CollectionVirtualFolders.allRecipesFolderId)]
        coordinator.selectedTab = .recipes

        coordinator.noteRecipesStackRebuilt()
        coordinator.handleDeepLink(.openRecipe(recipeId: "missing"))
        XCTAssertNil(coordinator.recipesStackPathToRestore(kept), "A deep link")

        coordinator.noteRecipesStackRebuilt()
        coordinator.handleTabSelection(.recipes)
        XCTAssertNil(coordinator.recipesStackPathToRestore(kept), "A tap on the selected Recipes tab")

        coordinator.noteRecipesStackRebuilt()
        coordinator.resetShellStateForLogout()
        XCTAssertNil(coordinator.recipesStackPathToRestore(kept), "Logout")

        coordinator.noteRecipesStackRebuilt()
        coordinator.cancelRecipesStackRestore()
        XCTAssertNil(coordinator.recipesStackPathToRestore(kept), "The recipe view closing itself")
    }

    func testADeletedRecipeIsNotPutBack() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.noteRecipesStackRebuilt()
        XCTAssertNil(coordinator.recipesStackPathToRestore([recipeRoute("deleted")]))
    }

    // MARK: - Spec 081 — iPad keyboard shortcuts (US6, T045)

    /// ⌘1–⌘4 switch the section without the tab tap's pop to the root.
    func testKeyboardTabSelectionKeepsTheSectionStacks() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .recipes
        coordinator.recipesPath.append(recipeRoute("open"))

        coordinator.selectTabFromKeyboard(.recipes)
        XCTAssertEqual(coordinator.recipesPath.count, 1, "⌘2 on «Рецепты» keeps the open recipe")

        coordinator.selectTabFromKeyboard(.shopping)
        XCTAssertEqual(coordinator.selectedTab, .shopping)
        coordinator.selectTabFromKeyboard(.recipes)
        XCTAssertEqual(coordinator.selectedTab, .recipes)
        XCTAssertEqual(coordinator.recipesPath.count, 1, "The way back keeps the open recipe")
    }

    /// ⌘4 in a wide window ends as the profile sheet; another section closes it.
    func testKeyboardProfileIsTheSheetInAWideWindow() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .shopping

        coordinator.selectTabFromKeyboard(.profile)
        // The shell's `onChange(of: selectedTab)` in a wide window.
        coordinator.normalizeProfileSelection(previous: coordinator.lastNonProfileTab, layoutMode: .padRegular)
        XCTAssertEqual(coordinator.selectedTab, .shopping)
        XCTAssertTrue(coordinator.isProfileSheetPresented)

        coordinator.selectTabFromKeyboard(.profile)
        XCTAssertTrue(coordinator.isProfileSheetPresented, "⌘4 again keeps the one sheet")

        coordinator.selectTabFromKeyboard(.shopping)
        XCTAssertFalse(coordinator.isProfileSheetPresented, "⌘3 under the sheet closes it")
        XCTAssertEqual(coordinator.selectedTab, .shopping)

        coordinator.presentProfileSheet()
        coordinator.selectTabFromKeyboard(.discover)
        XCTAssertFalse(coordinator.isProfileSheetPresented)
        XCTAssertEqual(coordinator.selectedTab, .discover)
    }

    /// ⌘F opens «Рецепты» and the list on screen takes the focus once, soon after.
    func testRecipeSearchFocusIsTakenOnceWithinItsWindow() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.selectedTab = .shopping
        coordinator.presentProfileSheet()
        let pressed = Date(timeIntervalSince1970: 1_000)
        let epoch = coordinator.recipeSearchFocusRequestEpoch

        coordinator.requestRecipeSearchFocus(at: pressed)
        XCTAssertEqual(coordinator.selectedTab, .recipes)
        XCTAssertFalse(coordinator.isProfileSheetPresented)
        XCTAssertEqual(coordinator.recipeSearchFocusRequestEpoch, epoch &+ 1)

        XCTAssertTrue(coordinator.consumeRecipeSearchFocusRequest(at: pressed.addingTimeInterval(0.5)))
        XCTAssertFalse(
            coordinator.consumeRecipeSearchFocusRequest(at: pressed.addingTimeInterval(0.6)),
            "A second list does not take the same ⌘F"
        )

        coordinator.requestRecipeSearchFocus(at: pressed)
        XCTAssertFalse(
            coordinator.consumeRecipeSearchFocusRequest(
                at: pressed.addingTimeInterval(AppShellCoordinator.recipeSearchFocusWindow + 0.1)
            ),
            "A list that appears long after ⌘F does not take it"
        )
        XCTAssertFalse(coordinator.consumeRecipeSearchFocusRequest(at: pressed), "No ⌘F, no focus")
    }

    /// ⇧⌘N asks the shell for the «Новая коллекция» alert and closes the profile sheet.
    func testNewCollectionRequestClosesTheProfileSheet() throws {
        let (coordinator, _, _) = try makeCoordinator()
        coordinator.presentProfileSheet()
        let epoch = coordinator.newCollectionRequestEpoch

        coordinator.requestNewCollection()

        XCTAssertEqual(coordinator.newCollectionRequestEpoch, epoch &+ 1)
        XCTAssertFalse(coordinator.isProfileSheetPresented)
    }

    private func recipeRoute(_ recipeId: String) -> RecipesRoute {
        .recipe(recipeId: recipeId, folderContext: nil)
    }

    private func makeEditableRecipe(id: String) -> RecipeData {
        RecipeData(
            id: id,
            name: "Шарлотка",
            servings: 4,
            color: "oklch(0.65 0.25 270)",
            version: "v3",
            description: "<p>Взбить яйца</p>",
            ingredients: [],
            nutrition: nil,
            isPublic: false,
            hasSteps: true,
            createdAt: "",
            updatedAt: "",
            imageUrl: nil,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )
    }
}

@MainActor
private final class FakeIPadSidebar: IPadSidebarControlling {
    var isSidebarShown: Bool
    let sidebarOverlaysContent: Bool
    /// `setSidebarHidden` arguments, in order.
    private(set) var calls: [Bool] = []

    init(shown: Bool, overlays: Bool = false) {
        isSidebarShown = shown
        sidebarOverlaysContent = overlays
    }

    func setSidebarHidden(_ hidden: Bool) {
        calls.append(hidden)
        isSidebarShown = !hidden
    }
}
