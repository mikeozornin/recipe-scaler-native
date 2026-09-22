import Foundation

enum IngredientNutritionViewMode: Sendable {
    case dish
    case per100g
    case perServing
    case scaled
}

enum IngredientNutritionDisplay {
    static func value(
        _ base: Double,
        ingredient: IngredientData,
        baseServings: Int,
        viewServings: Int,
        mode: IngredientNutritionViewMode
    ) -> Double {
        let baseS = max(1, baseServings)
        let factor = Double(max(1, viewServings)) / Double(baseS)
        return value(base, ingredient: ingredient, baseServings: baseServings, scaleFactor: factor, mode: mode)
    }

    static func value(
        _ base: Double,
        ingredient: IngredientData,
        baseServings: Int,
        scaleFactor: Double,
        mode: IngredientNutritionViewMode
    ) -> Double {
        guard base != 0 else { return 0 }

        switch mode {
        case .per100g:
            if let weight = ingredient.resolvedWeightGrams, weight > 0 {
                return (base / weight) * 100
            }
            return base
        case .perServing:
            let servings = max(1, baseServings)
            return base / Double(servings)
        case .scaled:
            let scale = scaleFactor.isFinite && scaleFactor > 0 ? scaleFactor : 1
            return base * scale
        case .dish:
            return base
        }
    }

    static func summaryLine(
        ingredient: IngredientData,
        baseServings: Int,
        viewServings: Int,
        mode: IngredientNutritionViewMode = .dish
    ) -> String? {
        let baseS = max(1, baseServings)
        let factor = Double(max(1, viewServings)) / Double(baseS)
        return summaryLine(ingredient: ingredient, baseServings: baseServings, scaleFactor: factor, mode: mode)
    }

    static func summaryLine(
        ingredient: IngredientData,
        baseServings: Int,
        scaleFactor: Double,
        mode: IngredientNutritionViewMode = .dish
    ) -> String? {
        guard ingredient.hasCompleteNutrition, !ingredient.isNutritionAllZero else { return nil }
        let cal = value(ingredient.calories ?? 0, ingredient: ingredient, baseServings: baseServings, scaleFactor: scaleFactor, mode: mode)
        let pro = value(ingredient.protein ?? 0, ingredient: ingredient, baseServings: baseServings, scaleFactor: scaleFactor, mode: mode)
        let fat = value(ingredient.fat ?? 0, ingredient: ingredient, baseServings: baseServings, scaleFactor: scaleFactor, mode: mode)
        let carbs = value(ingredient.carbs ?? 0, ingredient: ingredient, baseServings: baseServings, scaleFactor: scaleFactor, mode: mode)

        // TP14 [review #14]: NaN/Inf-safe rounding before Int cast.
        let calText = String(intRoundedClamped(cal))
        let proText = formatMacro(pro)
        let fatText = formatMacro(fat)
        let carbsText = formatMacro(carbs)

        return String(
            format: Bundle.currentLocalizedString("nutrition.ingredient.summary"),
            intRoundedClamped(cal),
            proText,
            fatText,
            carbsText
        )
    }

    private static func formatMacro(_ value: Double) -> String {
        // TP14 [review #14]: guard before Int cast.
        guard value.isFinite else { return "" }
        if value == floor(value), let intValue = Int(exactlySafe: value) {
            return String(intValue)
        }
        return AppNumberFormat.string(value, maximumFractionDigits: 1)
    }
}