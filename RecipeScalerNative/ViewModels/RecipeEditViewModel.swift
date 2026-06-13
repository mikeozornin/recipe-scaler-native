import Foundation
import SwiftUI

@MainActor
@Observable
final class RecipeEditViewModel {
    var draftServings: Int = 1
    var draftColor: String = "oklch(0.65 0.25 270)"
    private var colorBaseline: String = "oklch(0.65 0.25 270)"

    private let syncService: YjsSyncService
    private let recipeId: String
    /// Web `isEditingTitleRef` — not observed (avoids full detail view re-layout on title focus).
    var isEditingTitleField = false

    init(recipe: RecipeData, syncService: YjsSyncService) {
        self.recipeId = recipe.id
        self.syncService = syncService
        reset(from: recipe)
    }

    func reset(from recipe: RecipeData) {
        draftServings = max(1, recipe.servings)
        draftColor = recipe.color
        colorBaseline = recipe.color
    }

    /// Web parity: title writes on textarea `blur`, not on Done.
    func saveRecipeName(_ raw: String, against recipe: RecipeData) async throws {
        guard RecipeEditPolicy.canEdit(recipe: recipe) else {
            throw RecipeEditError.legacyFormatReadOnly
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = trimmed.isEmpty ? recipe.name : trimmed
        guard !effectiveName.isEmpty, effectiveName != recipe.name else { return }
        try await withSuspendedRecipeRefresh {
            try await syncService.updateRecipeName(effectiveName)
        }
    }

    /// Done: flush debounced Yjs + servings/color not yet written on blur.
    func finishEditing(against recipe: RecipeData) async throws {
        guard RecipeEditPolicy.canEdit(recipe: recipe) else {
            throw RecipeEditError.legacyFormatReadOnly
        }
        try await withSuspendedRecipeRefresh {
            if draftServings != recipe.servings {
                try await syncService.updateRecipeServings(draftServings)
            }
            if Self.colorsDiffer(draftColor, colorBaseline) {
                try await syncService.updateRecipeColor(draftColor)
                colorBaseline = RecipeAccentColor.normalizedStored(draftColor)
            }
            await syncService.flushPendingEdits()
        }
    }

    func saveIngredient(_ ingredient: IngredientData, existing: IngredientData?) async throws {
        try await withSuspendedRecipeRefresh {
            if let existing, existing.id == ingredient.id {
                try await syncService.updateIngredient(ingredient, markNutritionOutdated: true)
            } else {
                try await syncService.addIngredient(ingredient)
            }
            await syncAggregatedRecipeNutrition(replacing: ingredient)
        }
    }

    func saveIngredientNutrition(_ ingredient: IngredientData) async throws {
        try await withSuspendedRecipeRefresh {
            try await syncService.updateIngredient(ingredient, markNutritionOutdated: false)
            await syncAggregatedRecipeNutrition(replacing: ingredient)
        }
    }

    func deleteIngredient(id: String) async throws {
        try await withSuspendedRecipeRefresh {
            try await syncService.removeIngredient(id: id)
            await syncAggregatedRecipeNutrition()
        }
    }

    private func withSuspendedRecipeRefresh(_ body: () async throws -> Void) async rethrows {
        syncService.suspendRecipeRefresh()
        do {
            try await body()
            await syncService.resumeRecipeRefresh()
        } catch {
            await syncService.resumeRecipeRefresh()
            throw error
        }
    }

    func nextIngredientOrder(in recipe: RecipeData) -> Int {
        (recipe.ingredients.map(\.order).max() ?? 0) + 1
    }

    private func syncAggregatedRecipeNutrition(replacing updated: IngredientData? = nil) async {
        guard var ingredients = syncService.currentRecipe?.ingredients,
              syncService.currentRecipe?.id == recipeId else { return }
        if let updated, let index = ingredients.firstIndex(where: { $0.id == updated.id }) {
            ingredients[index] = updated
        }
        guard let totals = IngredientData.aggregatedMacros(from: ingredients) else { return }
        let nutrition = NutritionData(
            calories: totals.calories,
            protein: totals.protein,
            fat: totals.fat,
            carbs: totals.carbs,
            nutritionOutdated: false,
            extra: [:]
        )
        syncService.patchCurrentRecipeForEditing(nutrition: nutrition)
        try? await syncService.updateNutrition(
            calories: totals.calories,
            protein: totals.protein,
            fat: totals.fat,
            carbs: totals.carbs
        )
    }

    private static func colorsDiffer(_ lhs: String, _ rhs: String) -> Bool {
        RecipeAccentColor.normalizedStored(lhs) != RecipeAccentColor.normalizedStored(rhs)
    }
}