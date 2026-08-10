//
//  AppShellView.swift
//  RecipeScalerNative
//

import RecipeScalerCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AppShellView: View {
    @Bindable private var coordinator: AppShellCoordinator
    @Environment(YjsSyncService.self) private var syncService
    @Environment(AuthService.self) private var authService
    @Environment(TimerManager.self) private var timerManager
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(AssistantRecipeContext.self) private var assistantRecipeContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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

    private var layoutMode: LayoutMode {
        #if DEBUG
        if let forced = DebugLaunchOptions.forceLayout {
            return forced
        }
        #endif
        return LayoutModeResolver.resolve(
            horizontalSizeClass: horizontalSizeClass,
            forceLayout: nil
        )
    }

    @ViewBuilder
    private var shellContent: some View {
        switch layoutMode {
        case .compact:
            CompactAppShell(
                coordinator: coordinator,
                showAssistant: $showAssistant,
                mobileTimerPanelCollapsed: $mobileTimerPanelCollapsed,
                tabBarTopOffsetFromLayoutBottom: $tabBarTopOffsetFromLayoutBottom
            )
        case .regular:
            RegularAppShell(
                coordinator: coordinator,
                showAssistant: $showAssistant,
                assistantContextRecipeId: $assistantContextRecipeId
            )
        }
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
        shellContent
            .environment(coordinator)
            .environment(\.interactionProfile, InteractionProfile.current)
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
            .onChange(of: coordinator.pendingFileImportToast) { _, newValue in
                guard let newValue else { return }
                postTransientStatus(newValue)
                coordinator.pendingFileImportToast = nil
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
            if layoutMode == .compact, !showAssistant {
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
            coordinator.setRegularLayout(
                layoutMode == .regular,
                entries: syncService.collectionEntries
            )
            // Spec 059 fix: on cold launch iOS delivers the Universal Link URL
            // during splash, before `AppShellView` mounts. `onChange(pending)`
            // cannot observe a value that was already set, so a queued link
            // would be silently dropped and the app opened on the default tab.
            // Drain any pre-existing pending link once on appear.
            if let link = deepLinkRouter.pending {
                coordinator.handleDeepLink(link)
            }
        }
        .onChange(of: layoutMode) { _, mode in
            coordinator.setRegularLayout(
                mode == .regular,
                entries: syncService.collectionEntries
            )
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

            tabRoot(AccountView(auth: authService, timer: timerManager)) {
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
