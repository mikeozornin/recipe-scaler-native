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
#if os(macOS)
        // The native Mac detail column owns the inner HSplitView and needs a
        // stable minimum/ideal width. iPad regular lets NavigationSplitView
        // resolve the detail width from the current system geometry; applying
        // an infinite max constraint there can produce transient negative
        // frame dimensions while the sidebar is revealed or collapsed.
        .navigationSplitViewColumnWidth(
            min: 320,
            ideal: CGFloat(LayoutPreferencesStore.recipeListWidth + 400),
            max: .infinity
        )
#endif
        .onChange(of: syncService.collectionEntries) { _, entries in
            coordinator.restorePersistedWideFolderIfNeeded()
            if coordinator.wideRecipesState.activeFolderId == nil {
                coordinator.openFolderInWideSplit(nil)
            }
            coordinator.autoSelectFirstRecipeInWideSplitIfNeeded(entries: entries)
        }
        .onChange(of: syncService.folders) { _, _ in
            coordinator.restorePersistedWideFolderIfNeeded()
            if coordinator.wideRecipesState.activeFolderId == nil {
                coordinator.openFolderInWideSplit(nil)
            }
            coordinator.autoSelectFirstRecipeInWideSplitIfNeeded(
                entries: syncService.collectionEntries
            )
        }
        .onAppear {
            coordinator.restorePersistedWideFolderIfNeeded()
            if coordinator.wideRecipesState.activeFolderId == nil {
                coordinator.openFolderInWideSplit(nil)
            }
            coordinator.autoSelectFirstRecipeInWideSplitIfNeeded(entries: syncService.collectionEntries)
        }
    }

    @ViewBuilder
    private var recipeDetailPane: some View {
        if let recipeId = coordinator.wideRecipesState.selectedRecipeId {
            #if os(macOS)
            MacRecipeDetailView(
                recipeId: recipeId,
                onDeleted: { coordinator.selectRecipeInWideSplit(nil) }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            YDocRecipeDetailView(recipeId: recipeId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppSurface.background)
            #endif
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
        .background(AppSurface.background)
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
        #if os(macOS)
        MacRecipeListView(
            wideSelectedRecipeId: selectedRecipeBinding,
            activeFolderId: Binding(
                get: { coordinator.wideRecipesState.activeFolderId },
                set: { coordinator.openFolderInWideSplit($0) }
            )
        )
            .navigationSplitViewColumnWidth(
                min: CGFloat(LayoutPreferencesStore.recipeListWidthMin),
                ideal: CGFloat(LayoutPreferencesStore.recipeListWidth),
                max: CGFloat(LayoutPreferencesStore.recipeListWidthMax)
            )
        #else
        RecipeListView(
            navigationPath: $coordinator.recipesPath,
            wideSelectedRecipeId: selectedRecipeBinding,
            onFolderSelectionChanged: { folderId in
                coordinator.openFolderInWideSplit(folderId)
            }
        )
        .navigationSplitViewColumnWidth(
            min: CGFloat(LayoutPreferencesStore.recipeListWidthMin),
            ideal: CGFloat(LayoutPreferencesStore.recipeListWidth),
            max: CGFloat(LayoutPreferencesStore.recipeListWidthMax)
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: iPadRecipeListWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        }
        .onPreferenceChange(iPadRecipeListWidthPreferenceKey.self) { width in
            guard width >= CGFloat(LayoutPreferencesStore.recipeListWidthMin) else { return }
            let roundedWidth = width.rounded()
            guard abs(LayoutPreferencesStore.recipeListWidth - Double(roundedWidth)) > 1 else {
                return
            }
            LayoutPreferencesStore.recipeListWidth = Double(roundedWidth)
        }
        #endif
    }
}

#if !os(macOS)
private struct iPadRecipeListWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
#endif
