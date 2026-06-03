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
        case .importTab: "Import"
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

    var body: some View {
        VStack(spacing: 0) {
            MobileTimerPanel()
                .environmentObject(timerManager)

            TabView(selection: tabSelection) {
                // TEMPORARY: Discover tab hidden (re-enable when ready).
                // DiscoverRootView(path: $discoverPath)
                //     .tabItem { AppTabBarLabel(tab: .discover) }
                //     .tag(AppTab.discover)
                //     .accessibilityIdentifier(AccessibilityIdentifiers.tabDiscover)

                // TEMPORARY: Import tab hidden (re-enable when ready).
                // Color.clear
                //     .tabItem { AppTabBarLabel(tab: .importTab) }
                //     .tag(AppTab.importTab)
                //     .accessibilityIdentifier(AccessibilityIdentifiers.tabImport)

                RecipeListView(navigationPath: $recipesPath)
                    .tabItem { AppTabBarLabel(tab: .recipes) }
                    .tag(AppTab.recipes)
                    .accessibilityIdentifier(AccessibilityIdentifiers.tabRecipes)

                // TEMPORARY: Shopping tab hidden (re-enable when ready).
                // ShoppingListView(path: $shoppingPath)
                //     .tabItem { AppTabBarLabel(tab: .shopping) }
                //     .tag(AppTab.shopping)
                //     .accessibilityIdentifier(AccessibilityIdentifiers.tabShopping)

                AccountView()
                    .tabItem { AppTabBarLabel(tab: .profile) }
                    .tag(AppTab.profile)
                    .accessibilityIdentifier(AccessibilityIdentifiers.tabProfile)
            }
        }
        // TEMPORARY: Import sheet hidden (re-enable when ready).
        // .sheet(isPresented: $showImportSheet) {
        //     ImportRecipeSheet { result in
        //         showImportSheet = false
        //         selectedTab = .recipes
        //         if let id = result.primaryRecipeId {
        //             recipesPath.append(id)
        //         }
        //     }
        // }
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
        #if DEBUG
        .onAppear {
            openDebugTabIfNeeded()
            if DebugLaunchOptions.showAssistant {
                showAssistant = true
            }
        }
        #endif
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