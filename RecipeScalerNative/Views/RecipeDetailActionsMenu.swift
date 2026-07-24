//
//  RecipeDetailActionsMenu.swift
//  RecipeScalerNative
//

import SwiftUI

struct RecipeDetailActionsMenu: View {
    let recipeId: String
    let recipeName: String
    let ingredients: [IngredientData]
    let isEditing: Bool
    let isPinned: Bool

    @Environment(YjsSyncService.self) private var syncService

    @State private var recipePendingDelete = false
    @State private var showingAssignSheet = false

    var body: some View {
        Menu {
            if !isEditing {
                Button {
                    showingAssignSheet = true
                } label: {
                    AppLabel.make("collections.assign-tooltip", symbol: "folder.badge.plus")
                }

                Button {
                    Task { await togglePin() }
                } label: {
                    AppLabel.make(
                        isPinned ? "recipe.list.unpin" : "recipe.list.pin",
                        symbol: isPinned ? "pin.slash" : "pin"
                    )
                }

                Button {
                    Task { await addAllToShopping() }
                } label: {
                    AppLabel.make("shopping.detail-add-all", symbol: "cart.badge.plus")
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailMenuAddAllToShopping)

                Button(role: .destructive) {
                    recipePendingDelete = true
                } label: {
                    AppLabel.make("recipe.list.delete", symbol: "trash")
                }
            }
        } label: {
            AppToolbarStyle.iconOnly(systemName: "ellipsis")
        }
        .appToolbarIconButton()
        .accessibilityLabel("recipe.detail.more-actions")
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailMenu)
        .sheet(isPresented: $showingAssignSheet) {
            CollectionAssignSheet(recipeId: recipeId, recipeName: recipeName)
        }
        .alert(
            Bundle.currentLocalizedString("recipe.list.delete.confirm.title"),
            isPresented: $recipePendingDelete
        ) {
            Button(Bundle.currentLocalizedString("recipe.list.delete.confirm.action"), role: .destructive) {
                Task { await deleteRecipe() }
            }
            Button(Bundle.currentLocalizedString("recipe.list.delete.confirm.cancel"), role: .cancel) { }
        } message: {
            Text(
                String(
                    format: Bundle.currentLocalizedString("recipe.list.delete.confirm.message"),
                    locale: .current,
                    recipeName
                )
            )
        }
    }

    private func addAllToShopping() async {
        let items = ShoppingListFromRecipe.makeItems(
            recipeId: recipeId,
            recipeName: recipeName,
            ingredients: ingredients,
            ingredientIds: nil
        )
        guard !items.isEmpty else {
            postShoppingMessage(Bundle.currentLocalizedString("shopping.no-items-to-add"))
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
            postShoppingMessage(UserFacingAPIError.message(for: error))
        }
    }

    private func postShoppingMessage(_ message: String) {
        ShoppingFeedback.postStatus(message)
    }

    private func togglePin() async {
        do {
            try await syncService.setRecipePinned(recipeId: recipeId, isPinned: !isPinned)
        } catch {
            postShoppingMessage(UserFacingAPIError.message(for: error))
        }
    }

    private func deleteRecipe() async {
        do {
            try await syncService.deleteRecipeFromCollection(recipeId: recipeId)
        } catch {
            postShoppingMessage(UserFacingAPIError.message(for: error))
        }
    }
}
