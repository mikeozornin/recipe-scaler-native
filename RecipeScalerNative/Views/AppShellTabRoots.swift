import SwiftUI

/// Root views of the iOS 26.2+ shell tabs, shared by the iPhone `TabView`
/// (`AppShellView.modernTabBar`) and the iPad shell (spec 081, T013).
///
/// Each root gets the timer panel wiring of the modern `Tab { }` builder: the
/// collapsed flag in the environment and the expanded panel in a bottom bar.
/// Dependencies are passed in explicitly: tab content is built for bar items too,
/// where iOS 26 may hand it a fallback environment (`@Environment(Observable)` traps).
@MainActor
struct AppShellTabRoots {
    @Bindable var coordinator: AppShellCoordinator
    let syncService: YjsSyncService
    let authService: AuthService
    let timerManager: TimerManager
    let assistantRecipeContext: AssistantRecipeContext
    let vkusvillSettings: VkusvillSettingsStore
    let feedBadgeStore: FeedBadgeStore
    let appContainer: AppContainer?
    let scenePhase: ScenePhase
    let performLogoutTeardown: () async -> Void
    let mobileTimerPanelCollapsed: Bool
    let mobileTimerPanelCollapsedBinding: Binding<Bool>
    let showsMobileTimerPanelExpandedInset: Bool
    let mobileTimerPanelChevronNamespace: Namespace.ID

    func discover() -> some View {
        modernTabRoot(DiscoverRootView(
            path: $coordinator.discoverPath,
            feedBadgeStore: feedBadgeStore,
            coordinator: coordinator
        ))
    }

    func recipes() -> some View {
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
    }

    func shopping() -> some View {
        modernTabRoot(ShoppingListView(
            path: $coordinator.shoppingPath,
            syncService: syncService,
            timerManager: timerManager,
            coordinator: coordinator,
            authService: authService,
            vkusvillSettings: vkusvillSettings,
            mobileTimerPanelIsCollapsed: mobileTimerPanelCollapsed
        ))
    }

    func profile() -> some View {
        modernTabRoot(AccountView(
            auth: authService,
            timer: timerManager,
            vkusvillSettings: vkusvillSettings,
            performLogoutTeardown: performLogoutTeardown
        ))
    }

    /// Modern twin of `AppShellView.tabRoot` for the iOS 26 `Tab { }` builder — identical
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

    private var mobileTimerPanelExpandedInset: some View {
        MobileTimerPanel(timerManager: timerManager, isCollapsed: mobileTimerPanelCollapsedBinding, presentation: .insetExpanded)
            .environment(timerManager)
            .environment(\.mobileTimerPanelChevronNamespace, mobileTimerPanelChevronNamespace)
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
