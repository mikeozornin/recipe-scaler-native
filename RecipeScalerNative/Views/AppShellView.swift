//
//  AppShellView.swift
//  RecipeScalerNative
//

import RecipeScalerCore
import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Hashable {
    case discover
    case importTab
    case recipes
    case shopping
    case profile
    case assistant

    var title: LocalizedStringKey {
        switch self {
        case .discover: "discover.nav.discover"
        case .importTab: "discover.nav.import"
        case .recipes: "discover.nav.my-recipes"
        case .shopping: "discover.nav.shopping"
        case .profile: "discover.nav.profile"
        case .assistant: "assistant.title"
        }
    }

    /// Outline SF Symbol for `tabItem`. UITabBar draws the filled variant on the selected tab.
    /// Do not use `.fill` here — some glyphs (e.g. `square.and.arrow.down.fill`) do not exist and break tab icons.
    var tabBarSymbol: String {
        switch self {
        case .discover: "globe"
        case .importTab: "square.and.arrow.down"
        case .recipes: "book"
        case .shopping: "cart"
        case .profile: "person"
        case .assistant: "sparkles"
        }
    }

    /// Accessibility identifier applied to the `AppTabBarLabel` (the actual
    /// tab-bar button), so XCUITest can target `tab_discover` etc. directly.
    /// The modifier on `tabRoot(...)` in `tabView` does NOT propagate to the
    /// UITabBarButton — it lands on an inner container — so we attach it here
    /// on the label view instead.
    var accessibilityId: String {
        switch self {
        case .discover: AccessibilityIdentifiers.tabDiscover
        case .importTab:
            // Spec 074 — Import tab removed from the bar. The case survives
            // only for the DEBUG `-OpenTab=import` launch argument; this slug
            // is never attached to live UI.
            "debug-import"
        case .recipes: AccessibilityIdentifiers.tabRecipes
        case .shopping: AccessibilityIdentifiers.tabShopping
        case .profile: AccessibilityIdentifiers.tabProfile
        case .assistant: AccessibilityIdentifiers.tabAssistant
        }
    }
}

private struct AppTabBarLabel: View {
    let tab: AppTab

    var body: some View {
        Label(tab.title, systemImage: tab.tabBarSymbol)
            .font(AppTypography.tabBar)
            .accessibilityIdentifier(tab.accessibilityId)
    }
}

/// Red new-content dot (spec 072 US4) overlaid on the Discover tab icon.
/// `feedBadgeStore` is injected — tab labels are measured as bar items; after
/// assistant dismiss iOS 26 uses a fallback environment and
/// `@Environment(FeedBadgeStore.self)` traps.
private struct FeedBadgeTabLabel: View {
    let feedBadgeStore: FeedBadgeStore

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppTabBarLabel(tab: .discover)
            if feedBadgeStore.hasNew {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                    .offset(x: 8, y: -6)
            }
        }
    }
}

struct AppShellView: View {
    @Bindable private var coordinator: AppShellCoordinator
    @Environment(YjsSyncService.self) private var syncService
    @Environment(AuthService.self) private var authService
    @Environment(TimerManager.self) private var timerManager
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(AssistantRecipeContext.self) private var assistantRecipeContext
    @Environment(VkusvillSettingsStore.self) private var vkusvillSettings
    @Environment(OfflineBannerGate.self) private var offlineGate
    @Environment(FeedBadgeStore.self) private var feedBadgeStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAssistant = false
    @State private var assistantContextRecipeId: String?
    @State private var assistantOpenRequest: AssistantOpenRequest?
    @State private var transientStatus: TransientStatusPayload?
    @State private var transientStatusDismissTask: Task<Void, Never>?
    @State private var mobileTimerPanelCollapsed = true
    /// Spec 074 — TabView selection decoupled from `coordinator.selectedTab` so the
    /// fake assistant tab (`Color.clear`) never becomes the hosted tab root after a
    /// tap or dismiss (fixes shell chrome / safe-area corruption after sheet dismiss).
    @State private var tabViewSelection: AppTab = .recipes
    @Namespace private var mobileTimerPanelChevronNamespace

    /// Глобальный zoom-session для hero-фотографий (spec 064). `@State` +
    /// не-Observable holder, чтобы pinch/scroll ticks не пересобирали TabView.
    /// Overlay и сам hero подписаны на `context` через `@ObservedObject`.
    @State private var heroPhotoZoomSession = HeroPhotoZoomSession()

    init(coordinator: AppShellCoordinator) {
        _coordinator = Bindable(wrappedValue: coordinator)
    }

    /// Resolved from the environment's `AppContainer` (composition root owns
    /// teardown wiring); nil in previews/tests, where logout skips container
    /// teardown instead of touching a global.
    @Environment(\.appContainer) private var appContainer

    private var performLogoutTeardown: () async -> Void {
        let container = appContainer
        return {
            guard let container else { return }
            await container.sync.clearSessionForLogout()
            await container.stopForLogout()
        }
    }

    /// Spec 066 — ignore connection flaps while backgrounded; reset so lock
    /// time does not expire the banner delay (US1).
    private func applyOfflineBannerGate(for phase: ScenePhase) {
        switch phase {
        case .background:
            offlineGate.update(isNotConnected: false)
        case .active:
            applyOfflineBannerGate(isNotConnected: !syncService.connectionState.isConnected)
        default:
            break
        }
    }

    private func applyOfflineBannerGate(isNotConnected: Bool) {
        guard scenePhase == .active else { return }
        offlineGate.update(isNotConnected: isNotConnected)
    }

    private var mobileTimerPanelCollapsedBinding: Binding<Bool> {
        Binding(
            get: { mobileTimerPanelCollapsed },
            set: { newValue in
                withAnimation(MobileTimerPanelLayout.toggleAnimation) {
                    mobileTimerPanelCollapsed = newValue
                }
            }
        )
    }

    /// Routes a queued external assistant request only after the shell exists.
    /// The coordinator consumes the exact request id, so a newer request cannot
    /// be accidentally cleared by a delayed presentation callback.
    private func routePendingAssistantOpenRequest() {
        guard let request = coordinator.pendingAssistantOpenRequest else { return }
        coordinator.consumeAssistantOpenRequest(request)
        assistantOpenRequest = request
        assistantContextRecipeId = nil
        assistantRecipeContext.isAssistantSheetOpen = true
        showAssistant = true
    }

    /// Spec 074 — manual open (tab-bar entry, FAB replacement, adoption CTA).
    /// Manual open carries no external payload; `assistantOpenRequest` is reset
    /// so a stale request from a previous presentation cannot leak in.
    private func openAssistantManually() {
        assistantOpenRequest = nil
        assistantContextRecipeId = assistantRecipeContext.visibleRecipeId
        assistantRecipeContext.isAssistantSheetOpen = true
        showAssistant = true
        resyncTabViewSelectionAfterAssistantInteraction()
    }

    /// Keep TabView on the real tab; the assistant entry is a fake tab (sheet only).
    private func resyncTabViewSelectionAfterAssistantInteraction() {
        let tab = coordinator.selectedTab
        guard tab != .assistant else { return }
        tabViewSelection = tab
        #if DEBUG
        AgentSyncDebugLog.assistantLayout(
            hypothesisId: "H1",
            location: "AppShellView.resyncTabViewSelection",
            message: "tab_view_selection_resynced",
            data: ["tab": tab.rawValue]
        )
        #endif
    }

    /// Spec 040 — handlers for CTA taps in `FeatureAdoptionGuideView`.
    /// These are the app-level actions (tab switch, sheet, external Safari).
    /// The in-Profile scroll actions live in `AccountView` under a separate
    /// environment key (`featureAdoptionProfileScrollCta`) so the two never
    /// override each other.
    private func makeFeatureAdoptionAppCtaHandler() -> FeatureAdoptionAppCtaHandler {
        FeatureAdoptionAppCtaHandler(
            openAssistant: {
                Task { @MainActor in
                    openAssistantManually()
                }
            },
            openImport: {
                Task { @MainActor in
                    // Spec 074 — Import tab removed from the bar; the CTA
                    // presents the sheet directly over the current tab.
                    coordinator.presentImport()
                }
            },
            openSafari: { url in
                Task { @MainActor in
                    UIApplication.shared.open(url)
                }
            }
        )
    }

    var body: some View {
        shellObservers
            .environment(coordinator)
            .environment(
                \.featureAdoptionAppCta,
                makeFeatureAdoptionAppCtaHandler()
            )
    }

    /// `body` split: SwiftUI type-checker chokes on the full modifier chain
    /// (AppShellView body is one of the widest in the app), so overlays/sheets
    /// and lifecycle observers live in separate computed views.
    private var shellWithOverlays: some View {
        tabView
            .environment(\.heroPhotoZoomContext, heroPhotoZoomSession.context)
            .heroPhotoZoomOverlay(heroPhotoZoomSession.context)
            .overlay(alignment: .bottom) {
                if let transientStatus {
                    TransientStatusBanner(
                        message: transientStatus.message,
                        symbolName: transientStatus.symbolName
                    )
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 72)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: transientStatus != nil)
            .sheet(item: $coordinator.importPresentation) { _ in
                ImportRecipeSheet { result in
                    if let message = coordinator.completeImport(result) {
                        postTransientStatus(message)
                    }
                }
            }
            .modifier(AssistantSheetModifier(
                isPresented: $showAssistant,
                contextRecipeId: assistantContextRecipeId ?? assistantRecipeContext.visibleRecipeId,
                openRequest: assistantOpenRequest,
                onDismiss: {
                    #if DEBUG
                    // #region agent log
                    AgentSyncDebugLog.assistantLayout(
                        hypothesisId: "H1",
                        location: "AppShellView.assistantOnDismiss",
                        message: "assistant_sheet_onDismiss",
                        data: [
                            "selectedTab": coordinator.selectedTab.rawValue,
                            "showAssistant": showAssistant ? "true" : "false"
                        ]
                    )
                    AgentSyncDebugLog.logNavigationBarState(
                        hypothesisId: "H2",
                        location: "AppShellView.assistantOnDismiss",
                        tag: "sheet_onDismiss"
                    )
                    // #endregion
                    #endif
                    assistantRecipeContext.isAssistantSheetOpen = false
                    assistantContextRecipeId = nil
                    resyncTabViewSelectionAfterAssistantInteraction()
                },
                environmentCoordinator: coordinator,
                syncService: syncService,
                offlineGate: offlineGate,
                assistantRecipeContext: assistantRecipeContext
            ))
    }
    /// Lifecycle observers, split into small chains so the SwiftUI
    /// type-checker can handle each expression.
    private var shellObservers: some View {
        assistantObservers(on: transientStatusObservers(on: navigationObservers(on: shellWithOverlays)))
            .onAppear {
                tabViewSelection = coordinator.selectedTab
                RecipeImageDiskCache.migrateFromCachesIfNeeded()
                // Spec 059 fix: on cold launch iOS delivers the Universal Link URL
                // during splash, before `AppShellView` mounts. `onChange(pending)`
                // cannot observe a value that was already set, so a queued link
                // would be silently dropped and the app opened on the default tab.
                // Drain any pre-existing pending link once on appear.
                if let link = deepLinkRouter.pending {
                    coordinator.handleDeepLink(link)
                }
                // Spec 066 — arm gate from the current state; `onChange` above does
                // not fire for a value already set before this view mounted (cold
                // start already offline), so without this the banner would never appear.
                applyOfflineBannerGate(for: scenePhase)
                routePendingAssistantOpenRequest()
            }
            #if DEBUG
            .onAppear {
                coordinator.openDebugTabIfNeeded(DebugLaunchOptions.openTab)
                if DebugLaunchOptions.mobileTimerPanelExpanded {
                    mobileTimerPanelCollapsed = false
                }
                if DebugLaunchOptions.showAssistant {
                    openAssistantManually()
                }
                coordinator.consumePendingRecipeIdIfNeeded()
            }
            #else
            .onAppear {
                coordinator.consumePendingRecipeIdIfNeeded()
            }
            #endif
    }

    private func assistantObservers(on base: some View) -> some View {
        base
            .onChange(of: coordinator.pendingAssistantOpenRequest) { _, _ in
                routePendingAssistantOpenRequest()
            }
            .onChange(of: coordinator.pendingAssistantTabOpen) { _, isPending in
                guard isPending else { return }
                coordinator.consumeAssistantTabOpen()
                // PI-5: if an external request was routed in the same SwiftUI
                // transaction (both onChange handlers fire before the render),
                // it already set `assistantOpenRequest` and the sheet will
                // present its payload. A manual open would nil it out and the
                // message would be silently lost — skip the manual open.
                guard assistantOpenRequest == nil else { return }
                openAssistantManually()
            }
            .onChange(of: coordinator.selectedTab) { _, newTab in
                guard newTab != .assistant else { return }
                tabViewSelection = newTab
            }
            .onChange(of: showAssistant) { _, isOpen in
                assistantRecipeContext.isAssistantSheetOpen = isOpen
                #if DEBUG
                // #region agent log
                AgentSyncDebugLog.assistantLayout(
                    hypothesisId: "H1",
                    location: "AppShellView.showAssistant",
                    message: "assistant_sheet_visibility",
                    data: [
                        "isOpen": isOpen ? "true" : "false",
                        "selectedTab": coordinator.selectedTab.rawValue,
                        "tabViewSelection": tabViewSelection.rawValue
                    ]
                )
                if !isOpen {
                    AgentSyncDebugLog.logNavigationBarState(
                        hypothesisId: "H2",
                        location: "AppShellView.showAssistant",
                        tag: "sheet_closed"
                    )
                }
                // #endregion
                #endif
            }
    }

    private func transientStatusObservers(on base: some View) -> some View {
        base
            .onReceive(NotificationCenter.default.publisher(for: .shoppingStatusMessage)) { notification in
                let payload: TransientStatusPayload?
                if let typed = notification.object as? TransientStatusPayload {
                    payload = typed
                } else if let message = notification.object as? String, !message.isEmpty {
                    payload = TransientStatusPayload(message: message)
                } else {
                    payload = nil
                }
                guard let payload, !payload.message.isEmpty else { return }
                transientStatusDismissTask?.cancel()
                withAnimation(.easeInOut(duration: 0.25)) {
                    transientStatus = payload
                }
                let shown = payload
                transientStatusDismissTask = Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if transientStatus == shown {
                            transientStatus = nil
                        }
                    }
                }
            }
    }

    private func navigationObservers(on base: some View) -> some View {
        base
            .onChange(of: coordinator.pendingFileImportToast) { _, newValue in
                guard let newValue else { return }
                postTransientStatus(newValue)
                coordinator.pendingFileImportToast = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRecipeRequested)) { _ in
                coordinator.consumePendingRecipeIdIfNeeded()
            }
            .onChange(of: deepLinkRouter.pending) { _, link in
                guard let link else { return }
                coordinator.handleDeepLink(link)
            }
            .onChange(of: syncService.connectionState) { _, newState in
                applyOfflineBannerGate(isNotConnected: !newState.isConnected)
            }
            .onChange(of: scenePhase) { _, phase in
                applyOfflineBannerGate(for: phase)
            }
    }

    private var mobileTimerPanel: some View {
        MobileTimerPanel(timerManager: timerManager, isCollapsed: mobileTimerPanelCollapsedBinding, presentation: .legacy)
            .environment(timerManager)
    }

    private var mobileTimerPanelAccessory: some View {
        MobileTimerPanel(timerManager: timerManager, isCollapsed: mobileTimerPanelCollapsedBinding, presentation: .accessoryCollapsed)
            .environment(timerManager)
            .environment(\.mobileTimerPanelChevronNamespace, mobileTimerPanelChevronNamespace)
    }

    private var mobileTimerPanelExpandedInset: some View {
        MobileTimerPanel(timerManager: timerManager, isCollapsed: mobileTimerPanelCollapsedBinding, presentation: .insetExpanded)
            .environment(timerManager)
            .environment(\.mobileTimerPanelChevronNamespace, mobileTimerPanelChevronNamespace)
    }

    private var showsMobileTimerPanelAccessory: Bool {
        !timerManager.suppressPanelSafeAreaInset
            && !timerManager.activeTimers.isEmpty
            && mobileTimerPanelCollapsed
    }

    private var showsMobileTimerPanelExpandedInset: Bool {
        if #available(iOS 26.2, *) {
            return !timerManager.suppressPanelSafeAreaInset
                && !timerManager.activeTimers.isEmpty
                && !mobileTimerPanelCollapsed
        }
        return false
    }

    /// Spec 074 — dual TabView. The new `Tab { }` API cannot be mixed with the
    /// legacy `.tabItem` style in one TabView (type-checker fails), so the shell
    /// has two builders:
    ///  - iOS 26.2+: trailing `Tab(role: .search)` (Liquid Glass slot) → sheet;
    ///    no `.searchable` / no morph — fake selection via `handleTabSelection`.
    ///  - iOS < 26.2 (incl. 26.0/26.1): legacy fake tab (`Color.clear`) → sheet.
    ///    The modern path's timer panel (`tabViewBottomAccessory` / `safeAreaBar`)
    ///    only exists on 26.2+, so earlier 26.x must stay on the legacy builder
    ///    or its timer panel would silently disappear.
    @ViewBuilder
    private var tabView: some View {
        if #available(iOS 26.2, *) {
            modernTabView
        } else {
            legacyTabView
        }
    }

    @available(iOS 26.2, *)
    private var modernTabView: some View {
        modernTabBar
            .animation(MobileTimerPanelLayout.toggleAnimation, value: mobileTimerPanelCollapsed)
            .modifier(MobileTimerAccessoryModifier(
                isEnabled: showsMobileTimerPanelAccessory,
                accessory: mobileTimerPanelAccessory
            ))
    }

    @available(iOS 26.2, *)
    private var modernTabBar: some View {
        TabView(selection: modernTabSelection) {
            Tab(value: AppTab.discover) {
                modernTabRoot(DiscoverRootView(
                    path: $coordinator.discoverPath,
                    feedBadgeStore: feedBadgeStore,
                    coordinator: coordinator
                ))
            } label: {
                FeedBadgeTabLabel(feedBadgeStore: feedBadgeStore)
            }

            Tab(value: AppTab.recipes) {
                modernTabRoot(RecipeListView(
                    navigationPath: $coordinator.recipesPath,
                    syncService: syncService,
                    coordinator: coordinator,
                    assistantRecipeContext: assistantRecipeContext,
                    timerManager: timerManager,
                    apiClient: appContainer?.api ?? .shared,
                    appContainer: appContainer,
                    systemBannerStore: appContainer?.systemBanner ?? SystemBannerStore(),
                    mobileTimerPanelIsCollapsed: mobileTimerPanelCollapsed,
                    scenePhase: scenePhase
                ))
            } label: {
                AppTabBarLabel(tab: .recipes)
            }

            Tab(value: AppTab.shopping) {
                modernTabRoot(ShoppingListView(
                    path: $coordinator.shoppingPath,
                    syncService: syncService,
                    timerManager: timerManager,
                    coordinator: coordinator,
                    authService: authService,
                    vkusvillSettings: vkusvillSettings,
                    mobileTimerPanelIsCollapsed: mobileTimerPanelCollapsed
                ))
            } label: {
                AppTabBarLabel(tab: .shopping)
            }

            Tab(value: AppTab.profile) {
                modernTabRoot(AccountView(
                    auth: authService,
                    timer: timerManager,
                    vkusvillSettings: vkusvillSettings,
                    performLogoutTeardown: performLogoutTeardown
                ))
            } label: {
                AppTabBarLabel(tab: .profile)
            }

            // Spec 074 — fake assistant tab (sheet only). Without `role: .search`:
            // iOS 26.2+ search slot corrupts nav chrome after sheet dismiss.
            Tab(value: AppTab.assistant) {
                Color.clear
            } label: {
                AppTabBarLabel(tab: .assistant)
                    .accessibilityIdentifier(AccessibilityIdentifiers.tabAssistant)
            }
        }
    }

    @available(iOS 26.2, *)
    private var modernTabSelection: Binding<AppTab> {
        Binding(
            get: { tabViewSelection },
            set: { newTab in
                if newTab == .assistant {
                    openAssistantManually()
                    return
                }
                tabViewSelection = newTab
                coordinator.handleTabSelection(newTab)
            }
        )
    }

    private var legacyTabView: some View {
        legacyTabBar
    }

    private var legacyTabBar: some View {
        TabView(selection: tabSelection) {
            tabRoot(DiscoverRootView(
                    path: $coordinator.discoverPath,
                    feedBadgeStore: feedBadgeStore,
                    coordinator: coordinator
                )) { FeedBadgeTabLabel(feedBadgeStore: feedBadgeStore) }
                .tag(AppTab.discover)
                .accessibilityIdentifier(AccessibilityIdentifiers.tabDiscover)

            tabRoot(RecipeListView(
                navigationPath: $coordinator.recipesPath,
                syncService: syncService,
                coordinator: coordinator,
                assistantRecipeContext: assistantRecipeContext,
                timerManager: timerManager,
                apiClient: appContainer?.api ?? .shared,
                appContainer: appContainer,
                systemBannerStore: appContainer?.systemBanner ?? SystemBannerStore(),
                mobileTimerPanelIsCollapsed: mobileTimerPanelCollapsed,
                scenePhase: scenePhase
            )) {
                AppTabBarLabel(tab: .recipes)
            }
            .tag(AppTab.recipes)
            .accessibilityIdentifier(AccessibilityIdentifiers.tabRecipes)

            tabRoot(ShoppingListView(
                    path: $coordinator.shoppingPath,
                    syncService: syncService,
                    timerManager: timerManager,
                    coordinator: coordinator,
                    authService: authService,
                    vkusvillSettings: vkusvillSettings,
                    mobileTimerPanelIsCollapsed: mobileTimerPanelCollapsed
                )) {
                AppTabBarLabel(tab: .shopping)
            }
            .tag(AppTab.shopping)
            .accessibilityIdentifier(AccessibilityIdentifiers.tabShopping)

            tabRoot(AccountView(
                auth: authService,
                timer: timerManager,
                vkusvillSettings: vkusvillSettings,
                performLogoutTeardown: performLogoutTeardown
            )) {
                AppTabBarLabel(tab: .profile)
            }
            .tag(AppTab.profile)
            .accessibilityIdentifier(AccessibilityIdentifiers.tabProfile)

            tabRoot(Color.clear) { AppTabBarLabel(tab: .assistant) }
                .tag(AppTab.assistant)
                .accessibilityIdentifier(AccessibilityIdentifiers.tabAssistant)
        }
    }

    /// Timer panel between tab content and tab bar (must be on tab root, not on `TabView` — otherwise tab bar is hidden).
    /// On iOS < 26.2 — manual `safeAreaInset(.bottom)` with opaque `systemBackground`.
    /// On iOS 26.2+ — collapsed mini player via `.tabViewBottomAccessory` on `TabView`;
    /// expanded list via `safeAreaBar` on each tab root (accessory slot is single-row only).
    ///
    /// Stable hierarchy rule: the bottom bar is always applied on iOS 26.2+ (content is empty when collapsed).
    /// Switching `if/else` between inset and plain content recreates the `List` subtree
    /// and resets scroll position when toggling collapsed↔expanded.
    ///
    /// iOS 26 `safeAreaBar` (vs `safeAreaInset`) drives the system scroll-edge fade and,
    /// crucially, propagates the bottom inset into nested `List`/`ScrollView` inside
    /// `NavigationStack` so the last rows stay visible above the expanded panel.
    @ViewBuilder
    private func tabRoot<Content: View, Label: View>(
        _ content: Content,
        @ViewBuilder tabItem: () -> Label
    ) -> some View {
        let rooted = content
            .environment(\.mobileTimerPanelIsCollapsed, mobileTimerPanelCollapsed)

        if #available(iOS 26.2, *) {
            rooted
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    if showsMobileTimerPanelExpandedInset {
                        mobileTimerPanelExpandedInset
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .tabItem { tabItem() }
        } else {
            // Keep `safeAreaInset` always attached on iOS 18.x. Toggling inset on/off when
            // `suppressPanelSafeAreaInset` changes (recipe edit mode) recreated the tab subtree
            // and reset `YDocRecipeDetailView` `@State` (`isEditing` back to false).
            rooted
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !timerManager.suppressPanelSafeAreaInset {
                        mobileTimerPanel
                    }
                }
                .tabItem { tabItem() }
        }
    }

    /// Modern twin of `tabRoot` for the iOS 26 `Tab { }` builder — identical
    /// timer-panel wiring, without `.tabItem` (the label comes from `Tab`).
    private func modernTabRoot<Content: View>(
        _ content: Content
    ) -> some View {
        let rooted = content
            .environment(\.mobileTimerPanelIsCollapsed, mobileTimerPanelCollapsed)

        return rooted
            .modifier(ModernTabBottomBarModifier(
                showsExpandedInset: showsMobileTimerPanelExpandedInset,
                expandedPanel: mobileTimerPanelExpandedInset
            ))
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { tabViewSelection },
            set: { newTab in
                if newTab == .assistant {
                    openAssistantManually()
                    return
                }
                tabViewSelection = newTab
                coordinator.handleTabSelection(newTab)
            }
        )
    }
    private func postTransientStatus(_ message: String) {
        NotificationCenter.default.post(name: .shoppingStatusMessage, object: message)
    }
}

/// Spec 074 — availability-isolated `tabViewBottomAccessory` (iOS 26.2+). The
/// modern TabView gate in `AppShellView.tabView` is also 26.2+, so the `else`
/// branch here is unreachable in production and exists for type-checking only.
private struct MobileTimerAccessoryModifier<Accessory: View>: ViewModifier {
    let isEnabled: Bool
    let accessory: Accessory

    func body(content: Content) -> some View {
        if #available(iOS 26.2, *) {
            content
                .tabViewBottomAccessory(isEnabled: isEnabled) {
                    accessory
                }
        } else {
            content
        }
    }
}

/// Spec 074 — assistant sheet for all iOS versions (fake tab entry).
private struct AssistantSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let contextRecipeId: String?
    let openRequest: AssistantOpenRequest?
    let onDismiss: () -> Void
    let environmentCoordinator: AppShellCoordinator
    let syncService: YjsSyncService
    let offlineGate: OfflineBannerGate
    let assistantRecipeContext: AssistantRecipeContext

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                AssistantSheet(
                    contextRecipeId: contextRecipeId,
                    openRequest: openRequest,
                    syncService: syncService
                )
                .environment(environmentCoordinator)
                .environment(offlineGate)
                .environment(assistantRecipeContext)
                .appOpaqueSheetPresentationPlain()
            }
    }
}

/// iOS 26.2-only expanded timer inset over `safeAreaBar` — same wiring as the
/// legacy `tabRoot` 26.2 branch, isolated for the `Tab { }` builder.
private struct ModernTabBottomBarModifier<Panel: View>: ViewModifier {
    let showsExpandedInset: Bool
    let expandedPanel: Panel

    func body(content: Content) -> some View {
        if #available(iOS 26.2, *) {
            content
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    if showsExpandedInset {
                        expandedPanel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
        } else {
            content
        }
    }
}

