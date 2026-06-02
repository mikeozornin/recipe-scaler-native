import Foundation

/// Per-ingredient nutrition editing/display helpers (web `edit-ingredient-nutrition.tsx`).
enum IngredientNutritionEditing {
    struct Per100gValues: Sendable, Equatable {
        var calories: Double
        var protein: Double
        var fat: Double
        var carbs: Double
    }

    struct AbsoluteValues: Sendable, Equatable {
        var calories: Double
        var protein: Double
        var fat: Double
        var carbs: Double
    }

    static func per100gValues(from ingredient: IngredientData) -> Per100gValues {
        guard let weight = ingredient.resolvedWeightGrams, weight > 0 else {
            return Per100gValues(
                calories: ingredient.calories ?? 0,
                protein: ingredient.protein ?? 0,
                fat: ingredient.fat ?? 0,
                carbs: ingredient.carbs ?? 0
            )
        }
        return Per100gValues(
            calories: per100g(ingredient.calories, weight: weight),
            protein: per100g(ingredient.protein, weight: weight),
            fat: per100g(ingredient.fat, weight: weight),
            carbs: per100g(ingredient.carbs, weight: weight)
        )
    }

    static func absoluteValues(per100g: Per100gValues, weightGrams: Double?) -> AbsoluteValues {
        guard let weight = weightGrams, weight > 0 else {
            return AbsoluteValues(
                calories: per100g.calories,
                protein: per100g.protein,
                fat: per100g.fat,
                carbs: per100g.carbs
            )
        }
        return AbsoluteValues(
            calories: absolute(per100g.calories, weight: weight),
            protein: absolute(per100g.protein, weight: weight),
            fat: absolute(per100g.fat, weight: weight),
            carbs: absolute(per100g.carbs, weight: weight)
        )
    }

    private static func per100g(_ stored: Double?, weight: Double) -> Double {
        guard let stored, stored != 0 else { return 0 }
        return (stored / weight) * 100
    }

    private static func absolute(_ per100g: Double, weight: Double) -> Double {
        (per100g / 100) * weight
    }
}