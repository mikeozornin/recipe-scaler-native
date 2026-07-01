//
//  RegularAppShell.swift
//  RecipeScalerNative
//
//  Spec 043 — NavigationSplitView (iPad regular / Mac).
//

import SwiftUI

struct RegularAppShell: View {
    @Bindable var coordinator: AppShellCoordinator
    @Binding var showAssistant: Bool
    @Binding var assistantContextRecipeId: String?
    @State private var timerInspectorPresented = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @Environment(AuthService.self) private var authService
    @Environment(TimerManager.self) private var timerManager

    private var showsRecipesSplit: Bool {
        coordinator.selectedTab == .recipes
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AppSidebarView(coordinator: coordinator)
        } content: {
            if showsRecipesSplit {
                RecipesListSplitColumn(coordinator: coordinator)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        } detail: {
            regularDetailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .toolbar {
                    TimerInspectorToolbarContent(isInspectorPresented: $timerInspectorPresented)
                    RegularAssistantToolbar(
                        showAssistant: $showAssistant,
                        assistantContextRecipeId: $assistantContextRecipeId
                    )
                }
                .timerInspector(isPresented: $timerInspectorPresented)
        }
        .background(Color(.systemBackground))
        .onAppear {
            syncColumnVisibility()
        }
        .onChange(of: coordinator.selectedTab) { _, _ in
            syncColumnVisibility()
        }
    }

    private func syncColumnVisibility() {
        columnVisibility = showsRecipesSplit ? .automatic : .doubleColumn
    }

    @ViewBuilder
    private var regularDetailColumn: some View {
        if showsRecipesSplit {
            RecipesSplitColumns(
                coordinator: coordinator,
                showAssistant: $showAssistant,
                assistantContextRecipeId: $assistantContextRecipeId,
                timerInspectorPresented: $timerInspectorPresented
            )
        } else {
            RegularTabContent(
                coordinator: coordinator,
                auth: authService,
                timer: timerManager
            )
        }
    }
}

private struct RegularTabContent: View {
    @Bindable var coordinator: AppShellCoordinator
    let auth: AuthService
    let timer: TimerManager

    var body: some View {
        Group {
            switch coordinator.selectedTab {
            case .discover:
                DiscoverRootView(path: $coordinator.discoverPath)
            case .shopping:
                ShoppingListView(path: $coordinator.shoppingPath)
            case .profile:
                AccountView(auth: auth, timer: timer)
            case .importTab, .recipes:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct RegularAssistantToolbar: ToolbarContent {
    @Binding var showAssistant: Bool
    @Binding var assistantContextRecipeId: String?

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                assistantContextRecipeId = nil
                showAssistant = true
            } label: {
                AppToolbarStyle.iconOnly(systemName: "sparkles")
            }
            .appToolbarIconButton()
            .accessibilityLabel(Text("assistant.title"))
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantToolbarButton)
        }
    }
}
