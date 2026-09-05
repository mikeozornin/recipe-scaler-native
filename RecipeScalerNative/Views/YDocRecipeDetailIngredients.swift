//
//  YDocRecipeDetailIngredients.swift
//  RecipeScalerNative
//
//  Review 2026.09.04 №20 — extracted from `YDocRecipeDetailView.swift`:
//  ingredient mutations (save/nutrition/delete/illustration/add/reorder,
//  add-to-shopping) routed through `RecipeEditViewModel` + `YjsSyncService`.
//

import SwiftUI
import RecipeScalerCore

extension YDocRecipeDetailView {
    func saveIngredientNutrition(
        ingredientId: String,
        calories: Double,
        protein: Double,
        fat: Double,
        carbs: Double,
        editViewModel: RecipeEditViewModel
    ) async {
        guard !saveInFlight else { return }
        guard let base = syncService.currentRecipe?.ingredients.first(where: { $0.id == ingredientId }) else { return }
        let updated = base.withNutrition(calories: calories, protein: protein, fat: fat, carbs: carbs)
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.saveIngredientNutrition(updated)
        } catch {
            editErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    func saveIngredient(_ ingredient: IngredientData, existing: IngredientData?) async {
        guard let editViewModel, !saveInFlight else { return }
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.saveIngredient(ingredient, existing: existing)
        } catch {
            editErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    func deleteIngredient(id: String) async {
        guard let editViewModel, !saveInFlight else { return }
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.deleteIngredient(id: id)
        } catch {
            editErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    func applyIngredientIllustrationSelection(
        ingredientId: String,
        illustrationId: String,
        editViewModel: RecipeEditViewModel
    ) async {
        guard !saveInFlight else { return }
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.applyIngredientIllustrationPickerSelection(
                ingredientId: ingredientId,
                illustrationId: illustrationId
            )
            syncLazyResolvedIllustrationBinding(
                ingredientId: ingredientId,
                illustrationId: illustrationId,
                pickerCleared: false
            )
        } catch {
            editErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    func applyIngredientIllustrationClear(
        ingredientId: String,
        editViewModel: RecipeEditViewModel
    ) async {
        guard !saveInFlight else { return }
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.applyIngredientIllustrationPickerClear(ingredientId: ingredientId)
            syncLazyResolvedIllustrationBinding(
                ingredientId: ingredientId,
                illustrationId: nil,
                pickerCleared: true
            )
        } catch {
            editErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    func addIngredientToShopping(_ ingredient: IngredientData) async {
        guard let recipe else { return }
        let items = ShoppingListFromRecipe.makeItems(
            recipeId: recipeId,
            recipeName: recipe.name,
            ingredients: recipe.ingredients,
            ingredientIds: [ingredient.id]
        )
        guard !items.isEmpty else {
            ShoppingFeedback.postStatus(Bundle.currentLocalizedString("shopping.no-items-to-add"))
            return
        }
        do {
            try await syncService.addRecipeToShoppingList(
                recipeId: recipeId,
                recipeName: recipe.name,
                ingredients: recipe.ingredients,
                selectedIngredientIds: [ingredient.id]
            )
            ShoppingFeedback.postStatus(ShoppingAddFeedback.message(for: items.count))
        } catch {
            ShoppingFeedback.postStatus(UserFacingAPIError.message(for: error))
        }
    }

    func addIngredient(name: String, amount: String, in recipe: RecipeData, editViewModel: RecipeEditViewModel) async {
        let order = editViewModel.nextIngredientOrder(in: recipe)
        let isSeparator = name.range(of: #"^[-—–−]{2,}$"#, options: .regularExpression) != nil
        let parsed = IngredientData.parsedQuantity(amount)
        let placeholder = IngredientData(id: "new", name: name)
        let ingredient = IngredientData(
            id: UUID().uuidString,
            name: name,
            amount: isSeparator ? "" : parsed.originalAmount,
            originalAmount: isSeparator ? "" : parsed.originalAmount,
            unit: isSeparator ? "" : placeholder.preservedUnit(whenParsing: parsed),
            order: order,
            isSeparator: isSeparator,
            hasQuantity: isSeparator ? false : parsed.hasQuantity
        )
        await saveIngredient(ingredient, existing: nil)
    }

    func reorderIngredients(from: Int, to: Int) async {
        do {
            try await syncService.moveIngredient(fromIndex: from, toIndex: to)
        } catch {
            editErrorMessage = UserFacingAPIError.message(for: error)
        }
    }
}
