//
//  RecipesSplitColumns.swift
//  RecipeScalerNative
//
//  Spec 043 — recipe list + detail columns (regular layout).
//

import SwiftUI
import RecipeScalerCore

struct RecipesSplitColumns: View {
    @Bindable var coordinator: AppShellCoordinator
    @Binding var showAssistant: Bool
    @Binding var assistantContextRecipeId: String?
    @Binding var timerInspectorPresented: Bool
    @Environment(YjsSyncService.self) private var syncService

    var body: some View {
        Group {
            if coordinator.wideRecipesState.selectedRecipeId != nil {
                recipeDetailPane
            } else {
                recipeDetailEmpty
            }
        }
        .navigationSplitViewColumnWidth(
            min: 320,
            ideal: CGFloat(LayoutPreferencesStore.recipeListWidth + 400),
            max: .infinity
        )
        .onChange(of: syncService.collectionEntries) { _, entries in
            coordinator.autoSelectFirstRecipeInWideSplitIfNeeded(entries: entries)
        }
        .onAppear {
            coordinator.autoSelectFirstRecipeInWideSplitIfNeeded(entries: syncService.collectionEntries)
        }
    }

    @ViewBuilder
    private var recipeDetailPane: some View {
        if let recipeId = coordinator.wideRecipesState.selectedRecipeId {
            YDocRecipeDetailView(recipeId: recipeId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
        }
    }

    private var recipeDetailEmpty: some View {
        ContentUnavailableView {
            AppEmptyState.label("shell.recipe-split.select-recipe.title", symbol: "book")
        } description: {
            Text("shell.recipe-split.select-recipe.description")
                .appBody()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct RecipesListSplitColumn: View {
    @Bindable var coordinator: AppShellCoordinator

    private var selectedRecipeBinding: Binding<String?> {
        Binding(
            get: { coordinator.wideRecipesState.selectedRecipeId },
            set: { coordinator.selectRecipeInWideSplit($0) }
        )
    }

    var body: some View {
        RecipeListView(
            navigationPath: $coordinator.recipesPath,
            wideSelectedRecipeId: selectedRecipeBinding
        )
        .navigationSplitViewColumnWidth(
            min: CGFloat(LayoutPreferencesStore.recipeListWidthMin),
            ideal: CGFloat(LayoutPreferencesStore.recipeListWidth),
            max: 480
        )
    }
}