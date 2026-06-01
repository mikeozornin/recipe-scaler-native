import Foundation

/// Ingredient data from a recipe Y.Doc.
/// Read from `Y.Map` inside `Y.Array('ingredients')` (v2/v3) or parsed from JSON string (v1).
struct IngredientData: Identifiable, Sendable {
    let id: String
    let name: String
    let amount: String
    let originalAmount: String
    let order: Int

    /// Compute a scaled amount given target servings and base servings.
    /// Uses originalAmount as the base. Falls back to amount if originalAmount is empty.
    func scaled(targetServings: Int, baseServings: Int) -> String {
        let base = originalAmount.isEmpty ? amount : originalAmount
        return Self.scaleAmountString(base, factor: Double(targetServings) / Double(baseServings))
    }

    /// Parse a numeric prefix from an amount string (e.g., "200g" → 200.0, "1/2 cup" → 0.5)
    /// and apply the scaling factor. Non-numeric amounts are returned unchanged.
    static func scaleAmountString(_ amount: String, factor: Double) -> String {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return amount }

        // Try to parse "number + unit" pattern
        let pattern = /^(\d+(?:\.\d+)?)\s*(.*)/
        guard let match = trimmed.firstMatch(of: pattern) else {
            // Try fraction like "1/2"
            let fractionPattern = /^(\d+)\/(\d+)\s*(.*)/
            if let fmatch = trimmed.firstMatch(of: fractionPattern),
               let num = Double(fmatch.1),
               let den = Double(fmatch.2), den != 0 {
                let scaled = (num / den) * factor
                let unit = String(fmatch.3)
                return formatNumber(scaled) + (unit.isEmpty ? "" : " \(unit)")
            }
            return amount
        }

        guard let num = Double(match.1) else { return amount }
        let unit = String(match.2)
        let scaled = num * factor
        return formatNumber(scaled) + (unit.isEmpty ? "" : " \(unit)")
    }

    /// Format a number: show as integer if whole, otherwise with reasonable precision.
    private static func formatNumber(_ value: Double) -> String {
        if value == floor(value) && value < Double(Int.max) {
            return String(Int(value))
        }
        let formatted = String(format: "%.2f", value)
        // Remove trailing zeros
        return formatted.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}
