import Foundation

/// Nutrition data from a recipe Y.Doc.
/// Read from `Y.Map` (v2/v3) or parsed from JSON string (v1).
struct NutritionData: Sendable {
    let calories: Double?
    let protein: Double?
    let fat: Double?
    let carbs: Double?

    /// Additional custom nutrition fields beyond the standard four.
    let extra: [String: Double]
}
