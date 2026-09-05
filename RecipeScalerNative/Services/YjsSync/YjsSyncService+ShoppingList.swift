//
//  YjsSyncService+ShoppingList.swift
//  RecipeScalerNative
//
//  Review 2026.09.04 №5 — first slice of the YjsSyncService split (4693
//  lines, 18 responsibility zones). The shopping-list domain moves to its
//  own file behind the same `YjsSyncService` API; behavior is unchanged
//  (delegation to `DocumentManager` + snapshot refresh with session guards).
//  Next slices per the split plan: Export/Import, CollectionMutations,
//  RecipeImagePrefetcher.
//

import Foundation
import RecipeScalerCore

extension YjsSyncService {
    // MARK: - Shopping list

    func setShoppingSortMode(_ mode: ShoppingSortMode) async throws {
        try await documentManager.setShoppingSortMode(mode)
        await refreshShoppingSnapshot()
    }

    func setShoppingItemPurchased(id: String, purchased: Bool) async throws {
        try await documentManager.setShoppingItemPurchased(id: id, purchased: purchased)
        await refreshShoppingSnapshot()
    }

    func addManualShoppingItem(label: String) async throws {
        try await documentManager.addManualShoppingItem(label: label)
        await refreshShoppingSnapshot()
    }

    func addShoppingItem(_ item: ShoppingListItem) async throws {
        try await documentManager.addShoppingItems([item])
        await refreshShoppingSnapshot()
    }

    func removeShoppingItem(id: String) async throws {
        try await documentManager.removeShoppingItem(id: id)
        await refreshShoppingSnapshot()
    }

    func updateShoppingItemLabel(id: String, label: String) async throws {
        try await documentManager.updateShoppingItemLabel(id: id, label: label)
        await refreshShoppingSnapshot()
    }

    func clearPurchasedShoppingItems() async throws {
        try await documentManager.clearPurchasedShoppingItems()
        await refreshShoppingSnapshot()
    }

    /// DEBUG-only re-export of the screenshot-seed shopping list replace.
    /// See `DocumentManager.replaceShoppingItems` for the rationale.
    #if DEBUG
    func replaceShoppingItems(_ items: [ShoppingListItem]) async throws {
        try await documentManager.replaceShoppingItems(items)
        await refreshShoppingSnapshot()
    }
    #endif

    func addRecipeToShoppingList(
        recipeId: String,
        recipeName: String,
        ingredients: [IngredientData],
        selectedIngredientIds: Set<String>? = nil
    ) async throws {
        let items = ShoppingListFromRecipe.makeItems(
            recipeId: recipeId,
            recipeName: recipeName,
            ingredients: ingredients,
            ingredientIds: selectedIngredientIds
        )
        guard !items.isEmpty else { return }
        try await documentManager.addShoppingItems(items)
        await refreshShoppingSnapshot()
    }

    /// Loads recipe Y.Doc from local snapshot, then adds all eligible ingredients (recipe list swipe / menu parity).
    func addWholeRecipeToShoppingList(recipeId: String) async throws -> Int {
        guard let userId else { throw RecipeEditError.documentNotLoaded }
        _ = try? await documentManager.getOrCreateDoc(
            key: docKeyFor(recipeId: recipeId, userId: userId)
        )
        guard self.userId == userId else { throw RecipeEditError.documentNotLoaded }
        guard let recipe = try await documentManager.readRecipeData(recipeId: recipeId, userId: userId) else {
            throw RecipeEditError.documentNotLoaded
        }
        let items = ShoppingListFromRecipe.makeItems(
            recipeId: recipeId,
            recipeName: recipe.name,
            ingredients: recipe.ingredients,
            ingredientIds: nil
        )
        guard !items.isEmpty else { return 0 }
        try await documentManager.addShoppingItems(items)
        await refreshShoppingSnapshot()
        return items.count
    }
}
