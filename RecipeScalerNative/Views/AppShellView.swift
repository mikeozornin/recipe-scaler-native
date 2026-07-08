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
}

private struct AppTabBarLabel: View {
    let tab: AppTab

    var body: some View {
        Label(tab.title, systemImage: tab.tabBarSymbol)
            .font(AppTypography.tabBar)
    }
}

struct AppShellView: View {
    @Bindable private var coordinator: AppShellCoordinator
    @Environment(YjsSyncService.self) private var syncService
    @Environment(TimerManager.self) private var timerManager
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(AssistantRecipeContext.self) private var assistantRecipeContext
    @State private var showAssistant = false
    @State private var assistantContextRecipeId: String?
    @State private var transientStatusMessage: String?
    @State private var transientStatusDismissTask: Task<Void, Never>?
    @State private var mobileTimerPanelCollapsed = true
    @State private var tabBarTopOffsetFromLayoutBottom: CGFloat = 0
    @Namespace private var mobileTimerPanelChevronNamespace

    init(coordinator: AppShellCoordinator) {
        _coordinator = Bindable(wrappedValue: coordinator)
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
            .background {
                TabBarTopOffsetReader(offsetFromLayoutBottom: $tabBarTopOffsetFromLayoutBottom)
            }
            .overlay(alignment: .bottom) {
                if let transientStatusMessage {
                    TransientStatusBanner(message: transientStatusMessage)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 72)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: transientStatusMessage != nil)
            .sheet(item: $coordinator.importPresentation) { _ in
                ImportRecipeSheet { result in
                    if let message = coordinator.completeImport(result) {
                        postTransientStatus(message)
                    }
                }
            }
        .onChange(of: showAssistant) { _, isOpen in
            assistantRecipeContext.isAssistantSheetOpen = isOpen
        }
        .sheet(isPresented: $showAssistant, onDismiss: {
            assistantRecipeContext.isAssistantSheetOpen = false
            assistantContextRecipeId = nil
        }) {
            AssistantSheet(
                contextRecipeId: assistantContextRecipeId ?? assistantRecipeContext.visibleRecipeId
            )
        }
        .overlay(alignment: .bottomTrailing) {
            if !showAssistant {
                AssistantFabButton {
                    assistantContextRecipeId = assistantRecipeContext.visibleRecipeId
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
            guard let message = notification.object as? String, !message.isEmpty else { return }
            transientStatusDismissTask?.cancel()
            withAnimation(.easeInOut(duration: 0.25)) {
                transientStatusMessage = message
            }
            let shownMessage = message
            transientStatusDismissTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    if transientStatusMessage == shownMessage {
                        transientStatusMessage = nil
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
        .onAppear {
            RecipeImageDiskCache.migrateFromCachesIfNeeded()
        }
        #if DEBUG
        .onAppear {
            coordinator.openDebugTabIfNeeded(DebugLaunchOptions.openTab)
            if DebugLaunchOptions.mobileTimerPanelExpanded {
                mobileTimerPanelCollapsed = false
            }
            if DebugLaunchOptions.showAssistant {
                assistantContextRecipeId = assistantRecipeContext.visibleRecipeId
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

            tabRoot(AccountView()) {
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
