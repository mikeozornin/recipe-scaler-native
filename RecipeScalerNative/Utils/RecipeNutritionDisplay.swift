import Foundation
import SwiftUI

/// Recipe-level KBJU display aligned with web `nutrition-block.tsx`.
enum RecipeNutritionDisplay {
    /// Typography for macro columns (values 24 pt; labels web `text-[13px] mt-1`).
    enum Typography {
        static let macroValueSize: CGFloat = 24
        static let macroLabelSize: CGFloat = 13
        static let macroColumnSpacing: CGFloat = 8
        static let macroLabelTopSpacing: CGFloat = 4

        static var macroValueFont: Font {
            AppTypography.sansMedium(macroValueSize)
        }

        static var macroLabelFont: Font {
            AppTypography.sans(macroLabelSize)
        }
    }
    struct Macros: Sendable, Equatable {
        let calories: Double
        let protein: Double
        let fat: Double
        let carbs: Double
    }

    /// Total dish weight for per-100g mode (stored `totalWeight` or sum of ingredient weights).
    static func effectiveTotalWeight(from recipe: RecipeData) -> Double? {
        if let stored = recipe.nutrition?.extra["totalWeight"], stored > 0 {
            return stored
        }
        let sum = recipe.ingredients.compactMap(\.resolvedWeightGrams).reduce(0, +)
        return sum > 0 ? sum : nil
    }

    /// Prefer summed ingredient macros (web `effectiveNutrition`), else stored `nutrition` map.
    static func effectiveMacros(from recipe: RecipeData) -> Macros? {
        if let aggregated = IngredientData.aggregatedMacros(from: recipe.ingredients) {
            return Macros(
                calories: aggregated.calories,
                protein: aggregated.protein,
                fat: aggregated.fat,
                carbs: aggregated.carbs
            )
        }
        guard let nutrition = recipe.nutrition,
              let calories = nutrition.calories,
              let protein = nutrition.protein,
              let fat = nutrition.fat,
              let carbs = nutrition.carbs else { return nil }
        return Macros(calories: calories, protein: protein, fat: fat, carbs: carbs)
    }

    /// Applies the same view-mode rules as web before optional scale-factor (servings stepper).
    static func displayMacros(
        effective: Macros,
        baseServings: Int,
        viewServings: Int,
        recipeServings: Int,
        totalWeight: Double?,
        mode: IngredientNutritionViewMode
    ) -> Macros {
        var cal = effective.calories
        var pro = effective.protein
        var fat = effective.fat
        var carbs = effective.carbs

        switch mode {
        case .per100g:
            if let weight = totalWeight, weight > 0 {
                cal = (cal / weight) * 100
                pro = (pro / weight) * 100
                fat = (fat / weight) * 100
                carbs = (carbs / weight) * 100
            }
        case .perServing:
            let servings = max(1, recipeServings)
            cal /= Double(servings)
            pro /= Double(servings)
            fat /= Double(servings)
            carbs /= Double(servings)
        case .dish, .scaled:
            break
        }

        if mode == .scaled {
            let baseS = max(1, baseServings)
            let factor = Double(max(1, viewServings)) / Double(baseS)
            cal *= factor
            pro *= factor
            fat *= factor
            carbs *= factor
        }

        return Macros(
            calories: cal.rounded(),
            protein: pro,
            fat: fat,
            carbs: carbs
        )
    }

    static func formatCalories(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    static func formatMacroValue(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    static func formatScaleFactorLabel(_ scaleFactor: Double) -> String {
        let rounded = (scaleFactor * 100).rounded() / 100
        if rounded == floor(rounded) {
            return "×\(Int(rounded))"
        }
        var text = String(format: "%.2f", rounded)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            text.removeLast()
        }
        return "×\(text)"
    }
}