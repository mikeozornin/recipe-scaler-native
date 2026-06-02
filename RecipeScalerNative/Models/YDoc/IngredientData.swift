import Foundation

/// Ingredient data from a recipe Y.Doc.
/// Read from `Y.Map` inside `Y.Array('ingredients')` (v2/v3) or parsed from JSON string (v1).
struct IngredientData: Identifiable, Sendable {
    let id: String
    let name: String
    let amount: String
    let originalAmount: String
    let unit: String
    let order: Int
    let isSeparator: Bool
    /// `false` when `originalAmount` is null/absent (section header on web).
    let hasQuantity: Bool
    let calories: Double?
    let protein: Double?
    let fat: Double?
    let carbs: Double?
    let weight: Double?

    init(
        id: String,
        name: String,
        amount: String = "",
        originalAmount: String = "",
        unit: String = "",
        order: Int = 1,
        isSeparator: Bool = false,
        hasQuantity: Bool = true,
        calories: Double? = nil,
        protein: Double? = nil,
        fat: Double? = nil,
        carbs: Double? = nil,
        weight: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.originalAmount = originalAmount
        self.unit = unit
        self.order = order
        self.isSeparator = isSeparator
        self.hasQuantity = hasQuantity
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.weight = weight
    }

    /// All four macros present (web `hasNutrition` check).
    var hasCompleteNutrition: Bool {
        calories != nil && protein != nil && fat != nil && carbs != nil
    }

    var isNutritionAllZero: Bool {
        guard hasCompleteNutrition else { return true }
        return (calories ?? 0) == 0 && (protein ?? 0) == 0 && (fat ?? 0) == 0 && (carbs ?? 0) == 0
    }

    static func aggregatedMacros(from ingredients: [IngredientData]) -> (calories: Double, protein: Double, fat: Double, carbs: Double)? {
        let withNutrition = ingredients.filter(\.hasCompleteNutrition)
        guard !withNutrition.isEmpty else { return nil }
        return (
            calories: withNutrition.reduce(0) { $0 + ($1.calories ?? 0) },
            protein: withNutrition.reduce(0) { $0 + ($1.protein ?? 0) },
            fat: withNutrition.reduce(0) { $0 + ($1.fat ?? 0) },
            carbs: withNutrition.reduce(0) { $0 + ($1.carbs ?? 0) }
        )
    }

    func withNutrition(calories: Double, protein: Double, fat: Double, carbs: Double) -> IngredientData {
        IngredientData(
            id: id,
            name: name,
            amount: amount,
            originalAmount: originalAmount,
            unit: unit,
            order: order,
            isSeparator: isSeparator,
            hasQuantity: hasQuantity,
            calories: calories,
            protein: protein,
            fat: fat,
            carbs: carbs,
            weight: weight
        )
    }

    var isHeaderRow: Bool {
        if isSeparator { return true }
        if name.range(of: #"^[-—–−]{2,}$"#, options: .regularExpression) != nil {
            return true
        }
        return !hasQuantity
    }

    /// Numeric quantity only (web shows `originalAmount` without unit in the grid).
    var quantityText: String {
        guard hasQuantity else { return "" }
        if let value = numericValue {
            return Self.formatScalarNumber(value)
        }
        return originalAmount.isEmpty ? amount : originalAmount
    }

    func scaledQuantityText(targetServings: Int, baseServings: Int) -> String {
        guard !isHeaderRow, let value = numericValue else { return "" }
        let base = max(1, baseServings)
        let factor = Double(max(1, targetServings)) / Double(base)
        return Self.formatScalarNumber(value * factor)
    }

    var editableQuantity: String {
        quantityText
    }

    /// Legacy helper — prefer `scaledQuantityText`.
    func scaledDisplay(targetServings: Int, baseServings: Int) -> String {
        scaledQuantityText(targetServings: targetServings, baseServings: baseServings)
    }

    func scaled(targetServings: Int, baseServings: Int) -> String {
        scaledQuantityText(targetServings: targetServings, baseServings: baseServings)
    }

    var numericValue: Double? {
        let source = originalAmount.isEmpty ? amount : originalAmount
        let normalized = source.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else { return nil }
        return value
    }

    /// Gram weight for per-100g nutrition (`weight` field or quantity when unit is grams).
    var resolvedWeightGrams: Double? {
        if let weight, weight > 0 { return weight }
        let normalizedUnit = unit.trimmingCharacters(in: .whitespaces).lowercased()
        guard normalizedUnit.isEmpty || normalizedUnit == "г" || normalizedUnit == "g" else { return nil }
        guard let value = numericValue, value > 0 else { return nil }
        return value
    }

    /// Parse quantity field (digits only in UI; unit kept separately in Y.Doc).
    static func parsedQuantity(_ text: String) -> (originalAmount: String, hasQuantity: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", false) }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        if Double(normalized) != nil {
            return (normalized, true)
        }
        return (trimmed, true)
    }

    func preservedUnit(whenParsing parsed: (originalAmount: String, hasQuantity: Bool)) -> String {
        if !parsed.hasQuantity { return "" }
        if !unit.isEmpty { return unit }
        return "г"
    }

    static func formatScalarNumber(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "" }
        if value == floor(value) && abs(value) < Double(Int.max) {
            return String(Int(value))
        }
        let formatted = String(format: "%.2f", value)
        return formatted
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}