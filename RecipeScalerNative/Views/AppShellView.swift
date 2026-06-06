//
//  AppShellView.swift
//  RecipeScalerNative
//

import SwiftUI

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
    @StateObject private var timerManager = TimerManager.shared
    @State private var selectedTab: AppTab = .recipes
    @State private var previousTab: AppTab = .recipes
    @State private var showImportSheet = false
    @State private var showAssistant = false
    @State private var recipesPath = NavigationPath()
    @State private var discoverPath = NavigationPath()
    @State private var shoppingPath = NavigationPath()
    @State private var transientStatusMessage: String?
    @State private var transientStatusDismissTask: Task<Void, Never>?
    @State private var mobileTimerPanelCollapsed = true

    var body: some View {
        tabView
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
                        recipesPath.append(id)
                    }
                    if result.importedCount > 0 {
                        let message: String
                        if result.importedCount == 1 {
                            message = Bundle.currentLocalizedString("import.success")
                        } else {
                            let template = Bundle.currentLocalizedString("import.success-multiple")
                            message = String(
                                format: template,
                                locale: AppLanguagePreference.current.locale,
                                result.importedCount
                            )
                        }
                        postTransientStatus(message)
                    }
                }
                .presentationDetents([.large])
            }
        // TEMPORARY: Assistant button hidden (re-enable when ready).
        // .sheet(isPresented: $showAssistant) {
        //     AssistantSheet()
        // }
        // .overlay(alignment: .bottomTrailing) {
        //     Button {
        //         showAssistant = true
        //     } label: {
        //         AppSymbol.image("sparkles")
        //             .font(AppTypography.iconSize(AppTypography.title2Size))
        //             .foregroundStyle(.white)
        //             .padding(14)
        //             .background(Circle().fill(Color.accentColor))
        //     }
        //     .padding(.trailing, 16)
        //     .padding(.bottom, 72)
        //     .accessibilityIdentifier(AccessibilityIdentifiers.assistantFab)
        // }
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
        #if DEBUG
        .onAppear {
            openDebugTabIfNeeded()
            if DebugLaunchOptions.showAssistant {
                showAssistant = true
            }
        }
        #endif
    }

    private var mobileTimerPanel: some View {
        MobileTimerPanel(isCollapsed: $mobileTimerPanelCollapsed)
            .environmentObject(timerManager)
    }

    private var tabView: some View {
        TabView(selection: tabSelection) {
            // TEMPORARY: Discover tab hidden (re-enable when ready).
            // tabRoot(DiscoverRootView(path: $discoverPath)) { AppTabBarLabel(tab: .discover) }
            //     .tag(AppTab.discover)
            //     .accessibilityIdentifier(AccessibilityIdentifiers.tabDiscover)

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

    #if DEBUG
    private func openDebugTabIfNeeded() {
        guard let tab = DebugLaunchOptions.openTab else { return }
        if tab == .importTab {
            selectedTab = .recipes
            showImportSheet = true
        } else if tab == .discover {
            selectedTab = .recipes
        } else {
            selectedTab = tab
        }
    }

    #endif
}

#if DEBUG
#Preview {
    AppShellView()
}
#endif