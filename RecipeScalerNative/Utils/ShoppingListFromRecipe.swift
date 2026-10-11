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
            return "\(amount(amountPart, droppingUnitRepeatedIn: name))\(labelSeparator)\(name)"
        }
        return name.isEmpty ? amountPart : name
    }

    /// Ingredient names are stored with the unit (`"Вода, мл"`), so labels built as
    /// `amount unit · name` repeat it: `"100 мл · Вода, мл"` → `"100 · Вода, мл"`.
    /// Display-only for labels already in the list (written by older clients / web).
    static func displayLabel(for label: String) -> String {
        guard let range = label.range(of: labelSeparator) else { return label }
        let amountPart = String(label[..<range.lowerBound])
        let name = String(label[range.upperBound...])
        let amount = amount(amountPart, droppingUnitRepeatedIn: name)
        guard amount != amountPart else { return label }
        return "\(amount)\(labelSeparator)\(name)"
    }

    private static func amount(_ amountPart: String, droppingUnitRepeatedIn name: String) -> String {
        guard let comma = name.range(of: ", ", options: .backwards) else { return amountPart }
        let unit = name[comma.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unit.isEmpty,
              let unitRange = amountPart.range(of: " " + unit, options: [.backwards, .anchored, .caseInsensitive])
        else { return amountPart }
        let amount = amountPart[..<unitRange.lowerBound].trimmingCharacters(in: .whitespaces)
        return amount.isEmpty ? amountPart : amount
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