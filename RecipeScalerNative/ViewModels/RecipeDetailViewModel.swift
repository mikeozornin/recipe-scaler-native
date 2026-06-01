import Foundation

/// UI helpers for recipe detail backed by Y.Doc `RecipeData`.
@MainActor
enum RecipeDetailScaling {
    /// Map UI scale multiplier to target servings.
    static func targetServings(baseServings: Int, scaleFactor: Double) -> Int {
        max(1, Int((Double(baseServings) * scaleFactor).rounded()))
    }

    static func displayIngredients(
        from recipe: RecipeData,
        scaleFactor: Double
    ) -> [DisplayIngredient] {
        let base = max(1, recipe.servings)
        let target = targetServings(baseServings: base, scaleFactor: scaleFactor)

        return recipe.ingredients
            .sorted { $0.order < $1.order }
            .map { ingredient in
                let scaledText = ingredient.scaledDisplay(targetServings: target, baseServings: base)
                let (amount, unit) = splitAmountAndUnit(scaledText)
                return DisplayIngredient(
                    id: ingredient.id,
                    name: ingredient.name,
                    originalAmount: amount,
                    unit: unit,
                    order: ingredient.order,
                    isSeparator: ingredient.isHeaderRow,
                    amountDisplay: scaledText
                )
            }
    }

    private static func splitAmountAndUnit(_ value: String) -> (Double?, String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, "") }

        let pattern = /^(\d+(?:\.\d+)?)\s*(.*)/
        if let match = trimmed.firstMatch(of: pattern),
           let amount = Double(match.1) {
            return (amount, String(match.2))
        }

        let fractionPattern = /^(\d+)\/(\d+)\s*(.*)/
        if let match = trimmed.firstMatch(of: fractionPattern),
           let num = Double(match.1),
           let den = Double(match.2), den != 0 {
            return (num / den, String(match.3))
        }

        return (nil, trimmed)
    }
}