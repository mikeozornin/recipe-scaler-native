import Foundation

/// Nutrition data from a recipe Y.Doc.
/// Read from `Y.Map` (v2/v3) or parsed from JSON string (v1).
struct NutritionData: Sendable {
    let calories: Double?
    let protein: Double?
    let fat: Double?
    let carbs: Double?

    /// True when ingredient content changed (name/amount/add/delete) and
    /// the aggregated nutrition may no longer reflect the actual recipe.
    /// Set by the web client, server edit API, and native edit flow.
    let nutritionOutdated: Bool

    /// Additional custom nutrition fields beyond the standard four.
    let extra: [String: Double]
}
