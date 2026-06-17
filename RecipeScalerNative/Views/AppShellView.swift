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
    @EnvironmentObject private var syncService: YjsSyncService
    @State private var timerManager = TimerManager.shared
    @State private var deepLinkRouter = DeepLinkRouter.shared
    @State private var selectedTab: AppTab = .recipes
    @State private var previousTab: AppTab = .recipes
    @State private var showImportSheet = false
    @State private var showAssistant = false
    @State private var assistantContextRecipeId: String?
    @State private var recipesPath = NavigationPath()
    @State private var discoverPath = NavigationPath()
    @State private var shoppingPath = NavigationPath()
    @State private var transientStatusMessage: String?
    @State private var transientStatusDismissTask: Task<Void, Never>?
    @State private var mobileTimerPanelCollapsed = true
    @State private var spotlightOpenRecipeId: String?
    @State private var tabBarTopOffsetFromLayoutBottom: CGFloat = 0

    private static let assistantFabMargin: CGFloat = 16
    private static let assistantFabIconPadding: CGFloat = 14
    private static let assistantFabDiameter: CGFloat = AppTypography.title2Size + assistantFabIconPadding * 2

    private var assistantFabBottomPadding: CGFloat {
        let timerHeight = MobileTimerPanelLayout.height(
            timerCount: timerManager.timers.count,
            isExpanded: !mobileTimerPanelCollapsed
        )
        let tabBarOffset = tabBarTopOffsetFromLayoutBottom > 0
            ? tabBarTopOffsetFromLayoutBottom
            : Self.fallbackTabBarTopOffsetFromLayoutBottom
        return tabBarOffset + timerHeight + Self.assistantFabMargin
    }

    /// Tab bar height fallback until UIKit layout publishes a measured value.
    private static var fallbackTabBarTopOffsetFromLayoutBottom: CGFloat {
        49
    }

    var body: some View {
        tabView
            .background {
                TabBarTopOffsetReader(offsetFromLayoutBottom: $tabBarTopOffsetFromLayoutBottom)
            }
            .overlay(alignment: .bottom) {
                if let transientStatusMessage {
                    TransientStatusBanner(message: transientStatusMessage)
                        .padding(.bottom, 72)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: transientStatusMessage != nil)
            .sheet(isPresented: $showImportSheet) {
                ImportRecipeSheet { result in
                    showImportSheet = false
                    selectedTab = .recipes
                    if let id = result.primaryRecipeId {
                        recipesPath.append(RecipesRoute.recipe(recipeId: id, folderContext: nil))
                    }
                    if result.importedCount > 0 {
                        let message = Bundle.appPluralizedString(
                            key: "import.success",
                            count: result.importedCount
                        )
                        postTransientStatus(message)
                    }
                }
                .presentationDetents([.large])
            }
        .onChange(of: showAssistant) { _, isOpen in
            AssistantRecipeContext.shared.isAssistantSheetOpen = isOpen
        }
        .sheet(isPresented: $showAssistant, onDismiss: {
            AssistantRecipeContext.shared.isAssistantSheetOpen = false
            assistantContextRecipeId = nil
        }) {
            AssistantSheet(
                contextRecipeId: assistantContextRecipeId ?? AssistantRecipeContext.shared.visibleRecipeId
            )
                .environmentObject(syncService)
        }
        .overlay(alignment: .bottomTrailing) {
            if !showAssistant {
                Button {
                    assistantContextRecipeId = AssistantRecipeContext.shared.visibleRecipeId
                    AssistantRecipeContext.shared.isAssistantSheetOpen = true
                    showAssistant = true
                } label: {
                    AppSymbol.image("sparkles")
                        .font(AppTypography.iconSize(AppTypography.title2Size))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            Circle()
                                .fill(Color.accentColor)
                                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
                                .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 12)
                        }
                        .frame(width: Self.assistantFabDiameter, height: Self.assistantFabDiameter)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Self.assistantFabMargin)
                .padding(.bottom, assistantFabBottomPadding)
                .accessibilityIdentifier(AccessibilityIdentifiers.assistantFab)
                .accessibilityLabel(Text("assistant.title"))
            }
        }
        .onChange(of: selectedTab) { old, new in
            if new == .importTab {
                showImportSheet = true
                selectedTab = old
                return
            }
            if new == old {
                resetNestedNavigation(for: new)
            }
            previousTab = old
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
                    // Cancelled by a newer toast — do not clear the banner here.
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
            consumePendingDeepLinkIfNeeded()
        }
        .onChange(of: deepLinkRouter.pending) { _, link in
            guard let link else { return }
            handleDeepLink(link)
        }
        .onChange(of: syncService.collectionEntries) { _, entries in
            // If a Spotlight open is pending and the recipe just landed in the
            // collection, navigate now. Covers both first-sync after cold start
            // and offline → online transitions.
            guard let pendingId = spotlightOpenRecipeId else { return }
            if entries.contains(where: { $0.id == pendingId && !$0.deleted }) {
                spotlightOpenRecipeId = nil
                selectedTab = .recipes
                recipesPath.append(RecipesRoute.recipe(recipeId: pendingId, folderContext: nil))
            }
        }
        #if DEBUG
        .onAppear {
            openDebugTabIfNeeded()
            if DebugLaunchOptions.showAssistant {
                assistantContextRecipeId = AssistantRecipeContext.shared.visibleRecipeId
                AssistantRecipeContext.shared.isAssistantSheetOpen = true
                showAssistant = true
            }
            consumePendingDeepLinkIfNeeded()
        }
        #else
        .onAppear {
            consumePendingDeepLinkIfNeeded()
        }
        #endif
    }

    /// Open the recipe requested via `recipe-scaler://recipe/{id}` deep link,
    /// if any. Called on appear (cold start) and on `.openRecipeRequested` (warm start).
    private func consumePendingDeepLinkIfNeeded() {
        guard let id = DeepLinkRouter.consumePendingRecipeId() else { return }
        selectedTab = .recipes
        recipesPath.append(RecipesRoute.recipe(recipeId: id, folderContext: nil))
    }

    private var mobileTimerPanel: some View {
        MobileTimerPanel(isCollapsed: $mobileTimerPanelCollapsed)
            .environment(timerManager)
    }

    private var tabView: some View {
        TabView(selection: tabSelection) {
            tabRoot(DiscoverRootView(path: $discoverPath)) { AppTabBarLabel(tab: .discover) }
                .tag(AppTab.discover)
                .accessibilityIdentifier(AccessibilityIdentifiers.tabDiscover)

            tabRoot(Color.clear) { AppTabBarLabel(tab: .importTab) }
                .tag(AppTab.importTab)
                .accessibilityIdentifier(AccessibilityIdentifiers.tabImport)

            tabRoot(RecipeListView(navigationPath: $recipesPath)) {
                AppTabBarLabel(tab: .recipes)
            }
            .tag(AppTab.recipes)
            .accessibilityIdentifier(AccessibilityIdentifiers.tabRecipes)

            tabRoot(ShoppingListView(path: $shoppingPath)) {
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
    }

    /// Timer panel between tab content and tab bar (must be on tab root, not on `TabView` — otherwise tab bar is hidden).
    private func tabRoot<Content: View, Label: View>(
        _ content: Content,
        @ViewBuilder tabItem: () -> Label
    ) -> some View {
        content
            .environment(\.mobileTimerPanelIsCollapsed, mobileTimerPanelCollapsed)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                mobileTimerPanel
            }
            .tabItem { tabItem() }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .importTab {
                    showImportSheet = true
                } else if newValue == selectedTab {
                    resetNestedNavigation(for: newValue)
                } else {
                    selectedTab = newValue
                }
            }
        )
    }

    private func resetNestedNavigation(for tab: AppTab) {
        switch tab {
        case .discover:
            if !discoverPath.isEmpty { discoverPath = NavigationPath() }
        case .recipes:
            if !recipesPath.isEmpty { recipesPath = NavigationPath() }
        case .shopping:
            if !shoppingPath.isEmpty { shoppingPath = NavigationPath() }
        default:
            break
        }
    }

    private func postTransientStatus(_ message: String) {
        NotificationCenter.default.post(name: .shoppingStatusMessage, object: message)
    }

    // MARK: - Deep linking (Spotlight, future URL scheme / Universal Links)

    private func handleDeepLink(_ link: DeepLink) {
        switch link {
        case .openRecipe(let recipeId):
            selectedTab = .recipes
            if syncService.collectionEntries.contains(where: { $0.id == recipeId && !$0.deleted }) {
                spotlightOpenRecipeId = nil
                recipesPath.append(RecipesRoute.recipe(recipeId: recipeId, folderContext: nil))
            } else {
                // Recipe not yet in the loaded collection (cold start / offline
                // → online). Stash the id; `onChange(collectionEntries)` will
                // append it once it lands.
                spotlightOpenRecipeId = recipeId
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
                    ShoppingFeedback.postStatus(error.localizedDescription)
                }
            }
            deepLinkRouter.clear()
        case .openShoppingList:
            selectedTab = .shopping
            deepLinkRouter.clear()
        case .openHome:
            // No dedicated timers tab in the app — open the default tab.
            selectedTab = .recipes
            deepLinkRouter.clear()
        }
    }

    #if DEBUG
    private func openDebugTabIfNeeded() {
        guard let tab = DebugLaunchOptions.openTab else { return }
        if tab == .importTab {
            selectedTab = .recipes
            showImportSheet = true
        } else {
            selectedTab = tab
        }
    }

    #endif
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

private final class TabBarTopOffsetReaderViewController: UIViewController {
    var onOffsetChange: ((CGFloat) -> Void)?

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
              let tabBar = findTabBarController(in: window.rootViewController)?.tabBar else { return }
        let tabBarFrame = tabBar.convert(tabBar.bounds, to: window)
        let offsetFromWindowBottom = window.bounds.height - tabBarFrame.minY
        let offsetFromLayoutBottom = offsetFromWindowBottom - window.safeAreaInsets.bottom
        guard offsetFromLayoutBottom > 0 else { return }
        onOffsetChange?(offsetFromLayoutBottom)
    }

    private func findTabBarController(in viewController: UIViewController?) -> UITabBarController? {
        guard let viewController else { return nil }
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }
        for child in viewController.children {
            if let tabBarController = findTabBarController(in: child) {
                return tabBarController
            }
        }
        if let presented = viewController.presentedViewController,
           let tabBarController = findTabBarController(in: presented) {
            return tabBarController
        }
        return nil
    }
}

#if DEBUG
#Preview {
    AppShellView()
}
#endif