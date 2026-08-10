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
#if !os(macOS)
    @Environment(AuthService.self) private var authService
    @Environment(TimerManager.self) private var timerManager
#endif

    private var showsRecipesSplit: Bool {
        coordinator.selectedTab == .recipes
    }

    var body: some View {
#if os(macOS)
        macBody
#else
        iosBody
#endif
    }

#if !os(macOS)
    @ViewBuilder
    private var iosBody: some View {
        Group {
            if showsRecipesSplit {
                // Recipes uses the full iPad hierarchy: app sidebar → recipe
                // list → selected recipe detail.
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    AppSidebarView(coordinator: coordinator, showAssistant: $showAssistant)
                } content: {
                    RecipesListSplitColumn(coordinator: coordinator)
                } detail: {
                    regularDetailChrome
                }
                .onAppear {
                    syncColumnVisibility()
                }
            } else {
                // Other regular surfaces have no middle recipe-list column.
                // Use a real two-column split so changing to Discover,
                // Shopping or Profile never collapses the app sidebar as a
                // side effect of hiding an empty content column.
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    AppSidebarView(coordinator: coordinator, showAssistant: $showAssistant)
                } detail: {
                    regularDetailChrome
                }
                .onAppear {
                    syncColumnVisibility()
                }
            }
        }
        .background(AppSurface.background)
        .onChange(of: coordinator.selectedTab) { _, _ in
            syncColumnVisibility()
        }
    }

    private var regularDetailChrome: some View {
        regularDetailColumn
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppSurface.background)
            .toolbar {
                TimerInspectorToolbarContent(isInspectorPresented: $timerInspectorPresented)
                RegularAssistantToolbar(
                    showAssistant: $showAssistant,
                    assistantContextRecipeId: $assistantContextRecipeId,
                    contextRecipeId: coordinator.wideRecipesState.selectedRecipeId
                )
            }
            .timerInspector(isPresented: $timerInspectorPresented)
    }
#endif

#if os(macOS)
    @ViewBuilder
    private var macBody: some View {
        if showsRecipesSplit {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                AppSidebarView(coordinator: coordinator, showAssistant: $showAssistant)
            } content: {
                RecipesListSplitColumn(coordinator: coordinator)
            } detail: {
                applyMacDetailChrome(
                    RecipesSplitColumns(
                        coordinator: coordinator,
                        showAssistant: $showAssistant,
                        assistantContextRecipeId: $assistantContextRecipeId,
                        timerInspectorPresented: $timerInspectorPresented
                    )
                )
            }
            .background(AppSurface.background)
            .onAppear {
                // Establish the wide default once, but preserve an explicit
                // user collapse when returning to Recipes.
                if columnVisibility == .automatic {
                    columnVisibility = .all
                }
            }
        } else {
            // Non-recipe surfaces are already single-column Mac views. Use a
            // native two-column split here so the app sidebar sits directly
            // beside Discover/Shopping/Profile instead of leaving an empty
            // middle column from the recipe split.
            NavigationSplitView {
                AppSidebarView(coordinator: coordinator, showAssistant: $showAssistant)
            } detail: {
                applyMacDetailChrome(MacRegularTabContent(coordinator: coordinator))
            }
            .background(AppSurface.background)
        }
    }

    private func applyMacDetailChrome<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppSurface.background)
            .toolbar {
                TimerInspectorToolbarContent(isInspectorPresented: $timerInspectorPresented)
                RegularAssistantToolbar(
                    showAssistant: $showAssistant,
                    assistantContextRecipeId: $assistantContextRecipeId,
                    contextRecipeId: coordinator.wideRecipesState.selectedRecipeId
                )
            }
            .timerInspector(isPresented: $timerInspectorPresented)
    }
#endif

    private func syncColumnVisibility() {
#if os(macOS)
        // The native Mac recipes layout is intentionally a three-column shell:
        // app navigation, collections/recipes, and detail.
        //
        // Deferred to the next runloop tick because the sidebar's
        // `List(selection:)` mutates `coordinator.selectedTab` synchronously,
        // which triggers this `onChange` in the same render pass. Writing
        // `columnVisibility` synchronously would feed `NavigationSplitView`
        // two navigation mutations in one frame and trip
        // "NavigationRequestObserver tried to update multiple times per frame".
        let target: NavigationSplitViewVisibility = showsRecipesSplit ? .all : .doubleColumn
        Task { @MainActor in
            if columnVisibility != target {
                columnVisibility = target
            }
        }
#else
        // iOS owns sidebar collapse/restore for the current geometry and
        // system toggle. Do not overwrite that state when the selected
        // surface changes or when Stage Manager/rotation changes width.
        return
#endif
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
            #if os(macOS)
            MacRegularTabContent(coordinator: coordinator)
            #else
            RegularTabContent(
                coordinator: coordinator,
                auth: authService,
                timer: timerManager
            )
            #endif
        }
    }
}

#if !os(macOS)
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
        .background(AppSurface.background)
    }
}
#else
private struct MacRegularTabContent: View {
    @Bindable var coordinator: AppShellCoordinator

    var body: some View {
        Group {
            switch coordinator.selectedTab {
            case .discover:
                MacDiscoverView(path: $coordinator.discoverPath)
            case .shopping:
                MacShoppingListView(path: $coordinator.shoppingPath)
            case .profile:
                MacProfileView()
            case .importTab, .recipes:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSurface.background)
    }
}
#endif

struct RegularAssistantToolbar: ToolbarContent {
    @Binding var showAssistant: Bool
    @Binding var assistantContextRecipeId: String?
    let contextRecipeId: String?

    var body: some ToolbarContent {
        // The sidebar owns generic assistant launch. The toolbar button is
        // context-aware: it only appears when a recipe is selected in the
        // detail column, and it binds the new chat to that recipe.
        if let contextRecipeId {
            #if os(macOS)
            ToolbarItem {
                assistantButton(recipeId: contextRecipeId)
            }
            #else
            ToolbarItem(placement: .topBarTrailing) {
                assistantButton(recipeId: contextRecipeId)
            }
            #endif
        }
    }

    private func assistantButton(recipeId: String) -> some View {
        Button {
            assistantContextRecipeId = recipeId
            showAssistant = true
        } label: {
            AppToolbarStyle.iconOnly(systemName: "sparkles")
        }
        .appToolbarIconButton()
        .accessibilityLabel(Text("assistant.title"))
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantToolbarButton)
    }
}
