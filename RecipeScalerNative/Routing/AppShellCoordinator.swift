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
    var seedText: String = ""
    var autoSubmit: Bool = false
    /// When true, a successful import consumes the clipboard banner candidate.
    var consumesClipboard: Bool = false
}

struct AssistantOpenRequest: Equatable, Sendable {
    let requestId: Int
    let message: String
}

/// Spec 078 — one-shot shake entry: optional recipe auto-attach + voice start.
struct AssistantShakeOpenRequest: Equatable, Sendable {
    let requestId: Int
    /// When non-nil, auto-attach this recipe after the sheet presents.
    let attachRecipeId: String?
    /// When true (no open recipe), clear thread / start a fresh chat.
    let forceNewChat: Bool
    let startVoiceRecording: Bool

    static func make(
        requestId: Int,
        visibleRecipeId: String?,
        startVoiceRecording: Bool = true
    ) -> AssistantShakeOpenRequest {
        let trimmed = visibleRecipeId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipeId = (trimmed?.isEmpty == false) ? trimmed : nil
        return AssistantShakeOpenRequest(
            requestId: requestId,
            attachRecipeId: recipeId,
            forceNewChat: recipeId == nil,
            startVoiceRecording: startVoiceRecording
        )
    }
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

    var selectedTab: AppTab = .recipes {
        didSet {
            switch selectedTab {
            case .discover, .recipes, .shopping:
                lastNonProfileTab = selectedTab
            case .profile, .assistant, .importTab:
                break
            }
        }
    }
    var importPresentation: ImportPresentation?
    /// Recipes stack. Typed (not `NavigationPath`) so the iPad columns can read and write
    /// the same selection through `RecipesSelection` (spec 081, plan.md Р4). Never serialized.
    var recipesPath: [RecipesRoute] = [] {
        didSet {
            // The reflow's pop right after a layout change: the edit's view is being
            // rebuilt, and the keeper decides (`recipesStackPathToRestore`).
            guard !(recipesPath.isEmpty && isRecipesStackRestoreArmed()) else { return }
            endRecipeEditLeftBehind()
        }
    }
    var discoverPath = NavigationPath()
    var shoppingPath = NavigationPath()
    private(set) var pendingSpotlightRecipeId: String?
    /// When true, Profile (`AccountView`) should scroll to Reminders, enable sync, and open list picker.
    private(set) var pendingRemindersSetup = false
    /// Spec 057 — last user-facing toast message from a silent file import.
    /// AppShellView renders this as a transient overlay.
    var pendingFileImportToast: String?

    /// One-shot external assistant entry point (spec 072). The request remains
    /// queued until AppShellView has mounted the sheet, so a tap cannot be lost
    /// in the presentation transaction.
    private(set) var pendingAssistantOpenRequest: AssistantOpenRequest?

    /// Spec 074 — tab-bar assistant entry. Set by `handleTabSelection(.assistant)`,
    /// consumed by AppShellView's `onChange` which presents the sheet. The tab
    /// selection itself never changes (fake tab, same pattern as `importTab`).
    private(set) var pendingAssistantTabOpen = false

    /// Spec 081 (FR-021) — the pending open came from ✦ on «Покупки» / «Подборки»: the
    /// assistant opens a new chat instead of the recent one. Reset with the open.
    private(set) var pendingAssistantTabOpenStartsNewChat = false

    /// Spec 078 — shake-to-open queued until AppShellView presents / updates the sheet.
    private(set) var pendingShakeAssistantOpenRequest: AssistantShakeOpenRequest?

    /// Spec 081 (plan.md Р2a) — «Моё всё» as a form sheet in a wide iPad window; the only
    /// source of truth for that sheet. The selected section does not change.
    var isProfileSheetPresented = false

    /// Spec 081 (T024) — the recipe of the iPad split takes the whole section, the list
    /// column hidden («Развернуть», as Apple Notes). Kept for the session across tabs,
    /// never persisted. DEBUG `-IPadListHidden=1` starts expanded. Changed only through
    /// `setRecipeDetailExpanded`.
    private(set) var recipeDetailExpanded = DebugLaunchOptions.iPadListHidden

    /// The sidebar was beside the content when the recipe expanded and was hidden with
    /// it; «Свернуть» shows it again (`restoreSidebarHiddenByRecipeExpand`).
    private(set) var sidebarHiddenByRecipeExpand = false

    /// Spec 081 (US5, T041/T043) — the iPad recipe edit, kept here so it outlives the
    /// recipe view: a size class change or a resize between the split and the phone stack
    /// rebuilds that view, and the new one adopts the edit with its drafts and focus.
    /// The split reads it to hide the list (`IPadLayoutPolicy.resolve(isEditing:)`).
    /// Never set on the iPhone. Changed only through `beginRecipeEdit` / `endRecipeEdit`, and
    /// ended by a `recipesPath` change that leaves it behind (`endRecipeEditLeftBehind`).
    private(set) var recipeEdit: IPadRecipeEditSession?

    /// Recipes opened in edit on creation (`RecipesRoute.recipe(openInEditMode:)`) on the
    /// iPad: a rebuilt recipe view must not enter edit again after «Готово».
    private(set) var recipeIdsStartedInEdit: Set<String> = []

    /// Spec 081 — the iPad sidebar «Развернуть» hides and «Свернуть» brings back; set by
    /// `AppContainer` on iPadOS 26.2+, a fake in unit tests, `nil` on older systems.
    var iPadSidebar: (any IPadSidebarControlling)?

    /// Spec 081 — bumped each time the profile sheet closes, so the iPad sidebar footer
    /// reloads the name and avatar that may have changed in the sheet.
    private(set) var profileSheetRevision = 0

    /// Spec 081 (plan.md Р2a) — the section the profile sheet returns to when «Профиль»
    /// gets selected in a wide window (FR-004b). Real sections only.
    private(set) var lastNonProfileTab: AppTab = .recipes

    /// Consumes the pending tab-open flag after AppShellView presented the sheet.
    func consumeAssistantTabOpen() {
        pendingAssistantTabOpen = false
        pendingAssistantTabOpenStartsNewChat = false
    }

    /// Spec 081 — ✦ in an iPad toolbar: the same open (or, with the panel open, close) as
    /// the «Ассистент» tab. `startsNewChat`: ✦ on «Покупки» and «Подборки» (FR-021).
    func handleAssistantToolbarTap(startsNewChat: Bool) {
        pendingAssistantTabOpenStartsNewChat = startsNewChat
        pendingAssistantTabOpen = true
    }

    /// Queues a shake open. Idempotent against double presentation via requestId.
    func requestShakeAssistantOpen(visibleRecipeId: String?) {
        nextAssistantRequestId += 1
        pendingShakeAssistantOpenRequest = AssistantShakeOpenRequest.make(
            requestId: nextAssistantRequestId,
            visibleRecipeId: visibleRecipeId,
            startVoiceRecording: true
        )
    }

    func consumeShakeAssistantOpenRequest(_ request: AssistantShakeOpenRequest) {
        guard pendingShakeAssistantOpenRequest?.requestId == request.requestId else { return }
        pendingShakeAssistantOpenRequest = nil
    }

    private var nextAssistantRequestId = 0

    /// Spec 072 — digest push landing request for the «Моя лента» segment.
    /// Monotonic counter: `DiscoverRootView` observes it and switches the
    /// segment each time it bumps (deep link → segment while the tab is
    /// already visible). Counter (not Bool) so a second push tap after
    /// switching back to «Подборки» re-triggers the request.
    var discoverFeedRequestEpoch = 0

    /// Bumped on every shell-wide reset (logout / account switch) so any open
    /// assistant sheet can detect that its session no longer belongs to the
    /// active account and tear itself down (cancel stream / bootstrap tasks).
    private(set) var assistantSessionEpoch = 0

    /// Spec 076 — hide clipboard banner while Share / UL / file inbound is landing.
    private(set) var inboundClipboardSuppressed = false

    #if DEBUG
    /// One-shot guard for `-OpenRecipeId` / `-OpenRecipeName` shell navigation.
    private var didOpenDebugLaunchRecipe = false
    #endif

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
        if newTab == .assistant {
            // Spec 074 — fake tab: present the sheet over the current tab;
            // selection binding snaps back because `selectedTab` is unchanged.
            #if DEBUG
            // #region agent log
            AgentSyncDebugLog.assistantLayout(
                hypothesisId: "H3",
                location: "AppShellCoordinator.handleTabSelection",
                message: "assistant_tab_tapped",
                data: [
                    "selectedTab": selectedTab.rawValue,
                    "pendingTabOpen": "true"
                ]
            )
            // #endregion
            #endif
            pendingAssistantTabOpen = true
            return
        }
        if newTab == selectedTab {
            resetNestedNavigation(for: newTab)
        } else {
            selectedTab = newTab
        }
    }

    // MARK: - iPad profile sheet (spec 081, plan.md Р2a)

    func presentProfileSheet() {
        isProfileSheetPresented = true
    }

    /// `onDismiss` of the sheet (system swipe, tap outside or «Готово»).
    func profileSheetDidDismiss() {
        isProfileSheetPresented = false
        profileSheetRevision &+= 1
    }

    /// `.profile` selected in `.padRegular` (tab tap, ⌘4, `requestRemindersSetup`,
    /// `-OpenTab=profile`, widening on the Profile tab) → back to `previous`, sheet on top.
    /// The same with the sheet kept up after narrowing: no second profile under it.
    func normalizeProfileSelection(previous: AppTab?, layoutMode: AppLayoutMode) {
        let resolution = IPadProfileSheetPolicy.resolve(
            selected: selectedTab,
            previous: previous,
            layoutMode: layoutMode,
            isSheetPresented: isProfileSheetPresented
        )
        guard resolution.presentsSheet else { return }
        selectedTab = resolution.selected
        isProfileSheetPresented = true
    }

    func presentImport(
        seedText: String = "",
        autoSubmit: Bool = false,
        consumesClipboard: Bool = false
    ) {
        importPresentation = ImportPresentation(
            seedText: seedText,
            autoSubmit: autoSubmit,
            consumesClipboard: consumesClipboard
        )
    }

    func beginInboundClipboardSuppression() {
        inboundClipboardSuppressed = true
    }

    func endInboundClipboardSuppression() {
        inboundClipboardSuppressed = false
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

    // MARK: - Assistant external entry point

    /// Opens the assistant on a fresh thread and asks it to send `message`.
    /// Repeated identical messages still get distinct request ids.
    func openAssistantWithMessage(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        nextAssistantRequestId &+= 1
        pendingAssistantOpenRequest = AssistantOpenRequest(
            requestId: nextAssistantRequestId,
            message: trimmed
        )
    }

    /// A request is consumed only when AppShellView has copied it into the
    /// sheet input. A newer request must remain authoritative if callbacks race.
    func consumeAssistantOpenRequest(_ request: AssistantOpenRequest) {
        guard pendingAssistantOpenRequest?.requestId == request.requestId else { return }
        pendingAssistantOpenRequest = nil
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
        inboundClipboardSuppressed = true
        selectedTab = .recipes
        recipesPath.append(RecipesRoute.recipe(recipeId: id, folderContext: nil))
    }

    // MARK: - Deep linking (Spotlight, URL scheme, Universal Links)

    func handleDeepLink(_ link: DeepLink) {
        inboundClipboardSuppressed = true
        cancelRecipesStackRestore()
        switch link {
        case .openRecipe(let recipeId):
            selectedTab = .recipes
            // One assignment: an emptied path in between would end an edit of this very
            // recipe (`endRecipeEditLeftBehind`).
            if syncService.collectionEntries.contains(where: { $0.id == recipeId && !$0.deleted }) {
                pendingSpotlightRecipeId = nil
                recipesPath = [RecipesRoute.recipe(recipeId: recipeId, folderContext: nil)]
            } else {
                pendingSpotlightRecipeId = recipeId
                recipesPath = []
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
            recipesPath = []
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
        case .openFeedRecipe(let recipeId):
            // Spec 072 single-recipe push tap: «Моя лента» segment with the
            // recipe card pushed on top — back navigation returns to the
            // feed (product decision 2026-08-30). Segment activation works
            // through the same epoch flag as the digest landing.
            selectedTab = .discover
            discoverListState?.clearAll()
            discoverPath = NavigationPath()
            discoverFeedRequestEpoch += 1
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
        case .openDiscoverFeed:
            // Spec 072 digest push: land on the «Моя лента» segment. The
            // segment is ephemeral view state inside `DiscoverRootView`, so
            // the coordinator only flags the request; the view consumes it on
            // appear (mirrors the `pendingAssistantOpenRequest` one-shot
            // pattern) and lands back on «Подборки» next time.
            selectedTab = .discover
            discoverListState?.clearAll()
            discoverPath = NavigationPath()
            discoverFeedRequestEpoch += 1
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
        recipesPath.append(RecipesRoute.recipe(recipeId: pendingId, folderContext: nil))
    }

    // MARK: - DEBUG

    #if DEBUG
    /// Store / verify launches: open a recipe by id or name once the collection is loaded.
    /// Uses the shell `recipesPath` (same as Spotlight) so TabView lazy tabs cannot
    /// swallow a push that only happened inside `RecipeListView`.
    func openDebugRecipeIfNeeded(in entries: [CollectionEntry]) {
        guard !didOpenDebugLaunchRecipe else { return }
        let live = entries.filter { !$0.deleted }
        let recipeId: String?
        if let explicitId = DebugLaunchOptions.openRecipeId,
           live.contains(where: { $0.id == explicitId }) {
            recipeId = explicitId
        } else if let name = DebugLaunchOptions.openRecipeName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty {
            recipeId = live.first(where: { entry in
                let display = RecipeTitleEmoji.displayName(for: entry.name)
                return entry.name.caseInsensitiveCompare(name) == .orderedSame
                    || display.caseInsensitiveCompare(name) == .orderedSame
                    || entry.name.localizedCaseInsensitiveContains(name)
                    || display.localizedCaseInsensitiveContains(name)
            })?.id
        } else {
            recipeId = nil
        }
        guard let recipeId else { return }
        didOpenDebugLaunchRecipe = true
        selectedTab = .recipes
        cancelRecipesStackRestore()
        recipesPath = [RecipesRoute.recipe(recipeId: recipeId, folderContext: nil)]
        AppLog.info(.app, "debug_open_recipe_shell", data: ["recipeId": recipeId])
    }

    func openDebugTabIfNeeded(_ tab: AppTab?) {
        if let slug = DebugLaunchOptions.openDiscoverCollectionSlug, !slug.isEmpty {
            clearScreenshotNavigationOverrides()
            selectedTab = .discover
            discoverPath = NavigationPath()
            discoverPath.append(DiscoverRoute.collection(slug))
            return
        }
        if let username = DebugLaunchOptions.openDiscoverProfileUsername, !username.isEmpty {
            clearScreenshotNavigationOverrides()
            selectedTab = .discover
            discoverPath = NavigationPath()
            discoverPath.append(DiscoverRoute.profile(username))
            return
        }
        guard let tab else { return }
        if tab == .importTab {
            selectedTab = .recipes
            presentImport()
        } else if tab == .assistant {
            pendingAssistantTabOpen = true
        } else {
            selectedTab = tab
        }
    }

    private func clearScreenshotNavigationOverrides() {
        pendingSpotlightRecipeId = nil
        deepLinkRouter.clear()
        _ = DeepLinkRouter.consumePendingRecipeId()
    }
    #endif

    /// Clears tab stacks, import sheet, and queued deep links after logout or account switch.
    func resetShellStateForLogout() {
        importPresentation = nil
        inboundClipboardSuppressed = false
        pendingSpotlightRecipeId = nil
        pendingRemindersSetup = false
        // Invalidate any open assistant sheet: bumping the epoch makes the sheet's
        // `onChange` tear down its stream/bootstrap/send tasks, so a streaming
        // response or deferred autosend cannot write into a logged-out session.
        assistantSessionEpoch &+= 1
        pendingAssistantOpenRequest = nil
        pendingAssistantTabOpen = false
        pendingAssistantTabOpenStartsNewChat = false
        pendingShakeAssistantOpenRequest = nil
        isProfileSheetPresented = false
        // A sidebar hidden by «Развернуть» comes back with the reset, wherever the user is.
        if sidebarHiddenByRecipeExpand, iPadSidebar?.isSidebarShown == false {
            iPadSidebar?.setSidebarHidden(false)
        }
        recipeDetailExpanded = false
        sidebarHiddenByRecipeExpand = false
        recipeEdit = nil
        recipeIdsStartedInEdit = []
        discoverListState?.clearAll()
        selectedTab = .recipes
        lastNonProfileTab = .recipes
        cancelRecipesStackRestore()
        recipesPath = []
        discoverPath = NavigationPath()
        shoppingPath = NavigationPath()
        deepLinkRouter.clear()
        UserDefaults.standard.removeObject(forKey: DeepLinkRouter.pendingRecipeIdKey)
        AppGroup.userDefaults?.removeObject(forKey: DeepLinkRouter.pendingRecipeIdKey)
    }

    // MARK: - Recipe expand (spec 081, T024)

    /// «Развернуть» / «Свернуть» of the iPad recipe. Expanding hides a shown sidebar
    /// (remembering one that stood beside the content); collapsing brings that one back
    /// when the user is on Recipes in a wide window, else later
    /// (`restoreSidebarHiddenByRecipeExpand`). The caller animates.
    func setRecipeDetailExpanded(_ expanded: Bool, isPadRegular: Bool) {
        guard expanded != recipeDetailExpanded else { return }
        if expanded, let iPadSidebar {
            let decision = IPadLayoutPolicy.recipeExpandSidebar(
                shown: iPadSidebar.isSidebarShown,
                overlaysContent: iPadSidebar.sidebarOverlaysContent,
                hiddenByExpand: sidebarHiddenByRecipeExpand
            )
            sidebarHiddenByRecipeExpand = decision.rememberHidden
            if decision.hide {
                iPadSidebar.setSidebarHidden(true)
            }
        }
        recipeDetailExpanded = expanded
        if !expanded {
            restoreSidebarHiddenByRecipeExpand(isPadRegular: isPadRegular)
        }
    }

    /// Shows the sidebar «Развернуть» hid once the recipe is collapsed and the user is on
    /// Recipes in a wide window: called on collapse, on the return to Recipes and on the
    /// way back from a compact window.
    func restoreSidebarHiddenByRecipeExpand(isPadRegular: Bool) {
        // Only an edit of the open recipe keeps the sidebar hidden.
        let editsOpenRecipe = recipeEdit != nil
            && recipeEdit?.recipeId == RecipesSelection.selection(from: recipesPath).recipeId
        guard IPadLayoutPolicy.restoresSidebarHiddenByExpand(
            hiddenByExpand: sidebarHiddenByRecipeExpand,
            recipeExpanded: recipeDetailExpanded,
            recipeEditing: editsOpenRecipe,
            recipesTabSelected: selectedTab == .recipes,
            isPadRegular: isPadRegular
        ) else { return }
        sidebarHiddenByRecipeExpand = false
        if iPadSidebar?.isSidebarShown == false {
            iPadSidebar?.setSidebarHidden(false)
        }
    }

    // MARK: - Recipe edit on the iPad (spec 081, US5)

    /// The recipe view entered edit. A session of another recipe is replaced: one recipe
    /// is edited at a time.
    func beginRecipeEdit(_ session: IPadRecipeEditSession) {
        recipeEdit = session
    }

    func noteRecipeStartedInEdit(_ recipeId: String) {
        recipeIdsStartedInEdit.insert(recipeId)
    }

    /// «Готово», or the edited recipe left the screen for good. The recipe stays expanded
    /// (T043): «Свернуть» brings the list and a sidebar hidden for the edit back. Out of a
    /// regular window or on another tab, that sidebar waits as after «Свернуть».
    func endRecipeEdit(recipeId: String, isPadRegular: Bool) {
        guard recipeEdit?.recipeId == recipeId else { return }
        recipeEdit = nil
        restoreSidebarHiddenByRecipeExpand(isPadRegular: isPadRegular)
    }

    /// An edit no recipe view is in (the user left it on another tab, or its view is being
    /// rebuilt) ends once its recipe is no longer the open one: a deep link, an import or a
    /// deletion opened another or closed it while the view was away. On screen the leaving
    /// view ends it (`leaveIPadEditSession`). The reflow's pop after a layout change waits
    /// for the keeper's verdict (`recipesStackPathToRestore`). The sidebar comes back with
    /// «Свернуть» or the return to Recipes (`restoreSidebarHiddenByRecipeExpand`).
    private func endRecipeEditLeftBehind() {
        guard let recipeEdit, recipeEdit.owner == nil,
              RecipesSelection.selection(from: recipesPath).recipeId != recipeEdit.recipeId
        else { return }
        self.recipeEdit = nil
    }

    // MARK: - The recipes stack across a layout change (spec 081, FR-018, T043)

    /// When a layout change last rebuilt the recipes stack with the path it had; `nil` once
    /// spent or cancelled. Not observed: nothing draws it.
    @ObservationIgnored private var recipesStackRebuiltAt: Date?

    /// A layout change rebuilt the recipes stack with the path it had: the split turned
    /// into the phone stack (`IPadRecipesSplitView`) or the size class changed
    /// (`IPadAdaptiveTabView`). The reflow that follows may pop it (`IPadStackPathKeeper`).
    func noteRecipesStackRebuilt(at date: Date = .now) {
        recipesStackRebuiltAt = date
    }

    /// The app itself changes the recipes path (a deep link, a reset, the recipe view
    /// closing itself): an emptied path is not a reflow to undo.
    func cancelRecipesStackRestore() {
        recipesStackRebuiltAt = nil
    }

    /// The stack a layout change rebuilt was emptied: the path to put back, or `nil`. Only
    /// a pop right after the rebuild is the reflow's (`IPadLayoutPolicy.stackPathToRestore`),
    /// it is put back once, and never to a recipe that is gone meanwhile.
    /// An edit left behind by a pop that is not put back ends here (`endRecipeEditLeftBehind`).
    func recipesStackPathToRestore(_ kept: [RecipesRoute], at date: Date = .now) -> [RecipesRoute]? {
        let sinceRebuild = recipesStackRebuiltAt.map { date.timeIntervalSince($0) }
        recipesStackRebuiltAt = nil
        let entries = syncService.collectionEntries
        let restored = IPadLayoutPolicy.stackPathToRestore(kept, sinceRebuild: sinceRebuild) { recipeId in
            entries.contains { $0.id == recipeId && !$0.deleted }
        }
        if restored == nil { endRecipeEditLeftBehind() }
        return restored
    }

    /// A layout change has just rebuilt the recipes stack: an emptied path may be the
    /// reflow's pop, which the keeper puts back.
    private func isRecipesStackRestoreArmed(at date: Date = .now) -> Bool {
        guard let rebuiltAt = recipesStackRebuiltAt else { return false }
        let sinceRebuild = date.timeIntervalSince(rebuiltAt)
        return sinceRebuild >= 0 && sinceRebuild < IPadLayoutPolicy.stackReflowWindow
    }

    /// The sidebar's visibility as the shell reads it (`\.tabBarPlacement`). Shown again
    /// while «Развернуть» had hidden it — the user's toggle or the system — it is no longer
    /// ours to restore, so «Свернуть» does not fight the user.
    func noteSidebarShown(_ shown: Bool) {
        sidebarHiddenByRecipeExpand = IPadLayoutPolicy.sidebarStillHiddenByExpand(
            hiddenByExpand: sidebarHiddenByRecipeExpand,
            sidebarShown: shown
        )
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
            cancelRecipesStackRestore()
            if !recipesPath.isEmpty { recipesPath = [] }
        case .shopping:
            if !shoppingPath.isEmpty { shoppingPath = NavigationPath() }
        case .assistant:
            // Fake tab — no nested navigation to reset.
            break
        default:
            break
        }
    }
}
