//
//  ShoppingListFromRecipe.swift
//  RecipeScalerNative
//

import Foundation

enum ShoppingListFromRecipe {
    static let labelSeparator = " · "

    static func isIngredientEligible(_ ingredient: IngredientData) -> Bool {
        if ingredient.isSeparator || ingredient.isHeaderRow { return false }
        return ingredient.hasQuantity
    }

    static func label(for ingredient: IngredientData) -> String {
        guard isIngredientEligible(ingredient) else { return "" }
        let qty = ingredient.quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        let amountPart = [qty, ingredient.unit.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !amountPart.isEmpty, !name.isEmpty {
            return "\(amountPart)\(labelSeparator)\(name)"
        }
        return name.isEmpty ? amountPart : name
    }

    static func sortName(for label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: labelSeparator) {
            let name = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return trimmed
    }

    static func makeItems(
        recipeId: String,
        recipeName: String,
        ingredients: [IngredientData],
        ingredientIds: Set<String>? = nil
    ) -> [ShoppingListItem] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return ingredients.compactMap { ing in
            if let ids = ingredientIds, !ids.contains(ing.id) { return nil }
            let label = label(for: ing)
            guard !label.isEmpty else { return nil }
            let illustrationId = ing.illustrationId?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ShoppingListItem(
                label: label,
                recipeId: recipeId,
                ingredientId: ing.id,
                recipeName: recipeName,
                illustrationId: illustrationId?.isEmpty == false ? illustrationId : nil,
                createdAt: now
            )
        }
    }
}