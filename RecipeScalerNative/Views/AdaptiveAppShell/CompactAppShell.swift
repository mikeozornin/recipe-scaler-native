//
//  CompactAppShell.swift
//  RecipeScalerNative
//
//  Spec 043 — extracted phone TabView shell (007).
//

import SwiftUI
import UIKit

struct CompactAppShell: View {
    @Bindable var coordinator: AppShellCoordinator
    @Binding var showAssistant: Bool
    @Binding var mobileTimerPanelCollapsed: Bool
    @Binding var tabBarTopOffsetFromLayoutBottom: CGFloat
    @Namespace private var mobileTimerPanelChevronNamespace
    @Environment(TimerManager.self) private var timerManager
    @Environment(AuthService.self) private var authService

    var body: some View {
        tabView
            .background {
                TabBarTopOffsetReader(offsetFromLayoutBottom: $tabBarTopOffsetFromLayoutBottom)
            }
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

            tabRoot(
                RecipeListView(
                    navigationPath: $coordinator.recipesPath,
                    onRecipeSelectionChanged: { recipeId, folderContext in
                        if let recipeId {
                            coordinator.noteCompactRecipeSelection(
                                recipeId,
                                folderContext: folderContext
                            )
                        } else {
                            coordinator.clearCompactRecipeSelection()
                        }
                    },
                    onFolderSelectionChanged: { folderId in
                        coordinator.noteCompactFolderSelection(folderId)
                    }
                )
            ) {
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

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { coordinator.selectedTab },
            set: { coordinator.handleTabSelection($0) }
        )
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

    private var mobileTimerPanel: some View {
        MobileTimerPanel(isCollapsed: mobileTimerPanelCollapsedBinding, presentation: .legacy)
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
        } else if !timerManager.suppressPanelSafeAreaInset {
            rooted
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    mobileTimerPanel
                }
                .tabItem { tabItem() }
        } else {
            rooted
                .tabItem { tabItem() }
        }
    }
}
