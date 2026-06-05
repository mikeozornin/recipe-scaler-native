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

    var body: some View {
        Menu {
            if !isEditing {
                Toggle(isOn: Binding(
                    get: { isPublic },
                    set: { value in Task { try? await syncService.updateRecipeIsPublic(value) } }
                )) {
                    AppLabel.make(String(localized: "recipe.detail.public"), symbol: "globe")
                }

                Button {
                    Task { await addAllToShopping() }
                } label: {
                    AppLabel.make(String(localized: "shopping.detail-add-all"), symbol: "cart.badge.plus")
                }

                Button {
                    NotificationCenter.default.post(name: .openAppShoppingTab, object: nil)
                } label: {
                    AppLabel.make(String(localized: "shopping.detail-open-list"), symbol: "cart")
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
        let items = ShoppingListFromRecipe.makeItems(
            recipeId: recipeId,
            recipeName: recipeName,
            ingredients: ingredients,
            ingredientIds: nil
        )
        guard !items.isEmpty else {
            postShoppingMessage(String(localized: "shopping.no-items-to-add"))
            return
        }
        do {
            try await syncService.addRecipeToShoppingList(
                recipeId: recipeId,
                recipeName: recipeName,
                ingredients: ingredients,
                selectedIngredientIds: nil
            )
            postShoppingMessage(ShoppingAddFeedback.message(for: items.count))
        } catch {
            postShoppingMessage(error.localizedDescription)
        }
    }

    private func postShoppingMessage(_ message: String) {
        ShoppingFeedback.postStatus(message)
    }
}