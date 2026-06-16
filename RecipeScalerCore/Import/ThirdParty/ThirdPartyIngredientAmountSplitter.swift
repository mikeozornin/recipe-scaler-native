//
//  ThirdPartyIngredientAmountSplitter.swift
//  RecipeScalerCore
//

import Foundation

public enum ThirdPartyIngredientAmountSplitter {
    private static let quantityPattern = try! NSRegularExpression(
        pattern: #"^([\d.,/\s]+)\s*(g|kg|ml|l|oz|lb|cup|cups|tbsp|tsp|шт\.?)?$"#,
        options: [.caseInsensitive]
    )

    /// Splits a combined quantity string into numeric amount and unit.
    /// `"225 g"` → `("225", "g")`; `"3"` → `("3", "")`; `"1 head"` → `("1 head", "")`.
    public static func split(_ combined: String) -> (amount: String, unit: String) {
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = quantityPattern.firstMatch(in: trimmed, range: range),
              match.numberOfRanges == 3,
              let amountRange = Range(match.range(at: 1), in: trimmed),
              let unitRange = Range(match.range(at: 2), in: trimmed) else {
            return (trimmed, "")
        }

        let amount = String(trimmed[amountRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = String(trimmed[unitRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !amount.isEmpty, !unit.isEmpty else {
            return (trimmed, "")
        }
        return (amount, unit)
    }
}
