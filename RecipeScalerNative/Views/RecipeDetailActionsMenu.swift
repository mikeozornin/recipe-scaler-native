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

    @EnvironmentObject private var syncService: YjsSyncService

    @State private var recipePendingDelete = false
    @State private var showingAssignSheet = false

    var body: some View {
        Menu {
            if !isEditing {
                Button {
                    Task { await addAllToShopping() }
                } label: {
                    AppLabel.make(String(localized: "shopping.detail-add-all"), symbol: "cart.badge.plus")
                }

                Button {
                    Task { await togglePin() }
                } label: {
                    AppLabel.make(
                        isPinned
                            ? String(localized: "recipe.list.unpin")
                            : String(localized: "recipe.list.pin"),
                        symbol: isPinned ? "pin.slash" : "pin"
                    )
                }

                Button {
                    showingAssignSheet = true
                } label: {
                    AppLabel.make(String(localized: "collections.assign-tooltip"), symbol: "folder.badge.plus")
                }

                Button(role: .destructive) {
                    recipePendingDelete = true
                } label: {
                    AppLabel.make(String(localized: "recipe.list.delete"), symbol: "trash")
                }
            }
        } label: {
            AppToolbarStyle.iconOnly(systemName: "ellipsis")
        }
        .appToolbarIconButton()
        .accessibilityLabel(String(localized: "recipe.detail.more-actions"))
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailMenu)
        .sheet(isPresented: $showingAssignSheet) {
            CollectionAssignSheet(recipeId: recipeId, recipeName: recipeName)
        }
        .alert(
            String(localized: "recipe.list.delete.confirm.title"),
            isPresented: $recipePendingDelete
        ) {
            Button(String(localized: "recipe.list.delete.confirm.action"), role: .destructive) {
                Task { await deleteRecipe() }
            }
            Button(String(localized: "recipe.list.delete.confirm.cancel"), role: .cancel) { }
        } message: {
            Text(
                String(
                    format: String(localized: "recipe.list.delete.confirm.message"),
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

    private func togglePin() async {
        do {
            try await syncService.setRecipePinned(recipeId: recipeId, isPinned: !isPinned)
        } catch {
            postShoppingMessage(error.localizedDescription)
        }
    }

    private func deleteRecipe() async {
        do {
            try await syncService.deleteRecipeFromCollection(recipeId: recipeId)
        } catch {
            postShoppingMessage(error.localizedDescription)
        }
    }
}
