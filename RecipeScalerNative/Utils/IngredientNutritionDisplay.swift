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
            let baseS = max(1, baseServings)
            let factor = Double(max(1, viewServings)) / Double(baseS)
            return base * factor
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
        guard ingredient.hasCompleteNutrition, !ingredient.isNutritionAllZero else { return nil }
        let cal = value(ingredient.calories ?? 0, ingredient: ingredient, baseServings: baseServings, viewServings: viewServings, mode: mode)
        let pro = value(ingredient.protein ?? 0, ingredient: ingredient, baseServings: baseServings, viewServings: viewServings, mode: mode)
        let fat = value(ingredient.fat ?? 0, ingredient: ingredient, baseServings: baseServings, viewServings: viewServings, mode: mode)
        let carbs = value(ingredient.carbs ?? 0, ingredient: ingredient, baseServings: baseServings, viewServings: viewServings, mode: mode)

        let calText = String(Int(cal.rounded()))
        let proText = formatMacro(pro)
        let fatText = formatMacro(fat)
        let carbsText = formatMacro(carbs)

        return String(
            format: Bundle.currentLocalizedString("nutrition.ingredient.summary"),
            Int(cal.rounded()),
            proText,
            fatText,
            carbsText
        )
    }

    private static func formatMacro(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}