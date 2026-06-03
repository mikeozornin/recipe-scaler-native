//
//  RecipeDetailActionsMenu.swift
//  RecipeScalerNative
//

import SwiftUI

struct RecipeDetailActionsMenu: View {
    let recipeId: String
    let recipeName: String
    let ingredients: [IngredientData]
    let isPublic: Bool
    let isEditing: Bool

    @EnvironmentObject private var syncService: YjsSyncService
    @State private var statusMessage: String?

    var body: some View {
        Menu {
            if !isEditing {
                Toggle(isOn: Binding(
                    get: { isPublic },
                    set: { value in Task { try? await syncService.updateRecipeIsPublic(value) } }
                )) {
                    AppLabel.make("Public recipe", symbol: "globe")
                }

                Button {
                    Task { await addAllToShopping() }
                } label: {
                    AppLabel.make("Add to shopping list", symbol: "cart.badge.plus")
                }
            }
        } label: {
            AppToolbarStyle.iconOnly(systemName: "ellipsis")
        }
        .appToolbarIconButton()
        .accessibilityLabel(String(localized: "recipe.detail.more-actions"))
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailMenu)
    }

    private func addAllToShopping() async {
        do {
            try await syncService.addRecipeToShoppingList(
                recipeId: recipeId,
                recipeName: recipeName,
                ingredients: ingredients,
                selectedIngredientIds: nil
            )
            statusMessage = "Added to shopping list"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

}