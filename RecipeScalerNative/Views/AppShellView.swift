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

    var title: LocalizedStringKey {
        switch self {
        case .discover: "discover.nav.discover"
        case .importTab: "discover.nav.import"
        case .recipes: "discover.nav.my-recipes"
        case .shopping: "discover.nav.shopping"
        case .profile: "discover.nav.profile"
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
        case .importTab: AccessibilityIdentifiers.tabImport
        case .recipes: AccessibilityIdentifiers.tabRecipes
        case .shopping: AccessibilityIdentifiers.tabShopping
        case .profile: AccessibilityIdentifiers.tabProfile
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

struct AppShellView: View {
    @Bindable private var coordinator: AppShellCoordinator
    @Environment(YjsSyncService.self) private var syncService
    @Environment(AuthService.self) private var authService
    @Environment(TimerManager.self) private var timerManager
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(AssistantRecipeContext.self) private var assistantRecipeContext
    @Environment(VkusvillSettingsStore.self) private var vkusvillSettings
    @Environment(OfflineBannerGate.self) private var offlineGate
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAssistant = false
    @State private var assistantContextRecipeId: String?
    @State private var assistantOpenRequest: AssistantOpenRequest?
    @State private var transientStatus: TransientStatusPayload?
    @State private var transientStatusDismissTask: Task<Void, Never>?
    @State private var mobileTimerPanelCollapsed = true
    @State private var tabBarTopOffsetFromLayoutBottom: CGFloat = 0
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

    private var assistantFabBottomPadding: CGFloat {
        let timerHeight = MobileTimerPanelLayout.height(
            timerCount: timerManager.timers.count,
            isExpanded: !mobileTimerPanelCollapsed
        )
        let tabBarOffset = tabBarTopOffsetFromLayoutBottom > 0
            ? tabBarTopOffsetFromLayoutBottom
            : Self.fallbackTabBarTopOffsetFromLayoutBottom
        return tabBarOffset + timerHeight + AssistantFabStyle.margin
    }

    /// Tab bar height fallback until UIKit layout publishes a measured value.
    private static var fallbackTabBarTopOffsetFromLayoutBottom: CGFloat {
        49
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

    /// Spec 040 — handlers for CTA taps in `FeatureAdoptionGuideView`.
    /// Spec 040 — handlers for CTA taps in `FeatureAdoptionGuideView`.
    /// These are the app-level actions (tab switch, sheet, external Safari).
    /// The in-Profile scroll actions live in `AccountView` under a separate
    /// environment key (`featureAdoptionProfileScrollCta`) so the two never
    /// override each other.
    private func makeFeatureAdoptionAppCtaHandler() -> FeatureAdoptionAppCtaHandler {
        FeatureAdoptionAppCtaHandler(
            openAssistant: {
                Task { @MainActor in
                    // Manual open carries no external payload; reset so a stale
                    // request from a previous presentation cannot leak in.
                    assistantOpenRequest = nil
                    showAssistant = true
                    assistantRecipeContext.isAssistantSheetOpen = true
                }
            },
            openImport: {
                Task { @MainActor in
                    coordinator.selectedTab = .importTab
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
        tabView
            .environment(coordinator)
            .environment(
                \.featureAdoptionAppCta,
                makeFeatureAdoptionAppCtaHandler()
            )
            .environment(\.heroPhotoZoomContext, heroPhotoZoomSession.context)
            .background {
                TabBarTopOffsetReader(offsetFromLayoutBottom: $tabBarTopOffsetFromLayoutBottom)
            }
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
        .onChange(of: coordinator.pendingFileImportToast) { _, newValue in
            guard let newValue else { return }
            postTransientStatus(newValue)
            coordinator.pendingFileImportToast = nil
        }
        .onChange(of: coordinator.pendingAssistantOpenRequest) { _, _ in
            routePendingAssistantOpenRequest()
        }
        .onChange(of: showAssistant) { _, isOpen in
            assistantRecipeContext.isAssistantSheetOpen = isOpen
        }
        .sheet(isPresented: $showAssistant, onDismiss: {
            assistantRecipeContext.isAssistantSheetOpen = false
            assistantContextRecipeId = nil
            // Deliberately NOT clearing `assistantOpenRequest` here. A request
            // consumed by `routePendingAssistantOpenRequest` after our dismissal
            // started cannot be distinguished from the dismissing presentation's
            // own payload, so clearing here raced new external opens (review
            // finding: onDismiss could wipe an already-queued request). Stale
            // payloads are impossible instead: every manual open site below
            // assigns this field explicitly, and external requests overwrite it
            // synchronously before presenting.
        }) {
            AssistantSheet(
                contextRecipeId: assistantContextRecipeId ?? assistantRecipeContext.visibleRecipeId,
                openRequest: assistantOpenRequest
            )
            // Sheet content is hosted outside `tabView`; `.environment(coordinator)`
            // on the shell does not propagate here (fatal: missing AppShellCoordinator).
            .environment(coordinator)
        }
        .overlay(alignment: .bottomTrailing) {
            if !showAssistant {
                AssistantFabButton {
                    assistantContextRecipeId = assistantRecipeContext.visibleRecipeId
                    // Manual open carries no external payload; reset so a stale
                    // request from a previous presentation cannot leak in.
                    assistantOpenRequest = nil
                    assistantRecipeContext.isAssistantSheetOpen = true
                    showAssistant = true
                }
                .padding(.trailing, AssistantFabStyle.margin)
                .padding(.bottom, assistantFabBottomPadding)
                .accessibilityIdentifier(AccessibilityIdentifiers.assistantFab)
                .accessibilityLabel(Text("assistant.title"))
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .openRecipeRequested)) { _ in
            coordinator.consumePendingRecipeIdIfNeeded()
        }
        .onChange(of: deepLinkRouter.pending) { _, link in
            guard let link else { return }
            coordinator.handleDeepLink(link)
        }
        // Spec 066 — single writer for offline banner debounce.
        // Feature-gating views (AssistantSheet, disabled buttons, image refresh)
        // continue to read `connectionState.isConnected` directly (instant);
        // only status banners read `offlineGate` (debounced).
        //
        // Signal: `!connectionState.isConnected` (not NWPathMonitor). Airplane
        // mode oscillates connecting ↔ reconnecting without `.connected`; those
        // states must keep the arm running. Hide only on `.connected`.
        //
        // Background time must not count (US1): lock → `.disconnected` would
        // otherwise expire the 3s timer while the phone is locked, then flash
        // banners until reconnect. Reset on `.background`, ignore connection
        // updates until `.active`, then re-arm with a fresh window.
        .onChange(of: syncService.connectionState) { _, newState in
            applyOfflineBannerGate(isNotConnected: !newState.isConnected)
        }
        .onChange(of: scenePhase) { _, phase in
            applyOfflineBannerGate(for: phase)
        }
        .onAppear {
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
                assistantContextRecipeId = assistantRecipeContext.visibleRecipeId
                assistantOpenRequest = nil
                assistantRecipeContext.isAssistantSheetOpen = true
                showAssistant = true
            }
            coordinator.consumePendingRecipeIdIfNeeded()
        }
        #else
        .onAppear {
            coordinator.consumePendingRecipeIdIfNeeded()
        }
        #endif
    }

    private var mobileTimerPanel: some View {
        MobileTimerPanel(isCollapsed: mobileTimerPanelCollapsedBinding, presentation: .legacy)
            .environment(timerManager)
    }

    private var mobileTimerPanelAccessory: some View {
        MobileTimerPanel(isCollapsed: mobileTimerPanelCollapsedBinding, presentation: .accessoryCollapsed)
            .environment(timerManager)
            .environment(\.mobileTimerPanelChevronNamespace, mobileTimerPanelChevronNamespace)
    }

    private var mobileTimerPanelExpandedInset: some View {
        MobileTimerPanel(isCollapsed: mobileTimerPanelCollapsedBinding, presentation: .insetExpanded)
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

    @ViewBuilder
    private var tabView: some View {
        let tabs = TabView(selection: tabSelection) {
            tabRoot(DiscoverRootView(path: $coordinator.discoverPath)) { AppTabBarLabel(tab: .discover) }
                .tag(AppTab.discover)
                .accessibilityIdentifier(AccessibilityIdentifiers.tabDiscover)

            tabRoot(Color.clear) { AppTabBarLabel(tab: .importTab) }
                .tag(AppTab.importTab)
                .accessibilityIdentifier(AccessibilityIdentifiers.tabImport)

            tabRoot(RecipeListView(navigationPath: $coordinator.recipesPath)) {
                AppTabBarLabel(tab: .recipes)
            }
            .tag(AppTab.recipes)
            .accessibilityIdentifier(AccessibilityIdentifiers.tabRecipes)

            tabRoot(ShoppingListView(path: $coordinator.shoppingPath)) {
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
        }
        if #available(iOS 26.2, *) {
            tabs
                .animation(MobileTimerPanelLayout.toggleAnimation, value: mobileTimerPanelCollapsed)
                .tabViewBottomAccessory(isEnabled: showsMobileTimerPanelAccessory) {
                    mobileTimerPanelAccessory
                }
        } else {
            tabs
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

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { coordinator.selectedTab },
            set: { coordinator.handleTabSelection($0) }
        )
    }
    private func postTransientStatus(_ message: String) {
        NotificationCenter.default.post(name: .shoppingStatusMessage, object: message)
    }
}

private struct TabBarTopOffsetReader: UIViewControllerRepresentable {
    @Binding var offsetFromLayoutBottom: CGFloat

    func makeUIViewController(context: Context) -> TabBarTopOffsetReaderViewController {
        let controller = TabBarTopOffsetReaderViewController()
        controller.onOffsetChange = { newValue in
            guard offsetFromLayoutBottom != newValue else { return }
            offsetFromLayoutBottom = newValue
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: TabBarTopOffsetReaderViewController, context: Context) {
        uiViewController.onOffsetChange = { newValue in
            guard offsetFromLayoutBottom != newValue else { return }
            offsetFromLayoutBottom = newValue
        }
        uiViewController.view.setNeedsLayout()
    }
}

/// Resolves the `UITabBarController` hosting a window's root view-controller
/// hierarchy. Caches the resolved controller and only re-runs the recursive
/// search when the cached reference is missing (controller deallocated) or its
/// `parent` has changed (modal presentation / reparenting), so a stable layout
/// does not walk the view-controller hierarchy on every `viewDidLayoutSubviews`.
///
/// `search` is injectable so tests can count traversals without polluting
/// production code with test hooks.
final class TabBarDiscovery {
    private weak var cached: UITabBarController?
    private var cachedParent: UIViewController?
    private let search: (UIViewController?) -> UITabBarController?

    init(search: @escaping (UIViewController?) -> UITabBarController? = TabBarDiscovery.find) {
        self.search = search
    }

    func resolve(root: UIViewController?) -> UITabBarController? {
        if let cached, cached.parent === cachedParent {
            return cached
        }
        let resolved = search(root)
        cached = resolved
        cachedParent = resolved?.parent
        return resolved
    }

    static func find(in viewController: UIViewController?) -> UITabBarController? {
        guard let viewController else { return nil }
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }
        for child in viewController.children {
            if let tabBarController = find(in: child) {
                return tabBarController
            }
        }
        if let presented = viewController.presentedViewController,
           let tabBarController = find(in: presented) {
            return tabBarController
        }
        return nil
    }
}

private final class TabBarTopOffsetReaderViewController: UIViewController {
    var onOffsetChange: ((CGFloat) -> Void)?
    private let tabBarDiscovery = TabBarDiscovery()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        publishOffsetIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        publishOffsetIfNeeded()
    }

    private func publishOffsetIfNeeded() {
        guard let window = view.window,
              let tabBar = tabBarDiscovery.resolve(root: window.rootViewController)?.tabBar else { return }
        let tabBarFrame = tabBar.convert(tabBar.bounds, to: window)
        let offsetFromWindowBottom = window.bounds.height - tabBarFrame.minY
        let offsetFromLayoutBottom = offsetFromWindowBottom - window.safeAreaInsets.bottom
        guard offsetFromLayoutBottom > 0 else { return }
        onOffsetChange?(offsetFromLayoutBottom)
    }
}
