//
//  ThirdPartyIngredientAmountSplitter.swift
//  RecipeScalerCore
//

import Foundation

public enum ThirdPartyIngredientAmountSplitter {
    /// MIK-145 [review #62]: no unit recognition — extracts only the leading
    /// numeric token into `amount`. Any non-numeric trailing text causes the
    /// whole input to be returned as `amount` (unit stays empty). This avoids
    /// the previous divergence where `cups` survived in Paprika but was
    /// canonicalized to `cup` in Crouton.
    //
    // MIK-143 [review #59]: safe static-init — `try?` + nil-guard in consumer.
    private static let quantityPattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^([\d.,/\s]+)$"#
    )

    /// Splits a combined quantity string. Numeric-only input (`"225"`, `"1.5"`,
    /// `"1/2"`) → `(amount, "")`. Anything else → `(input, "")`.
    public static func split(_ combined: String) -> (amount: String, unit: String) {
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }
        guard let quantityPattern else { return (trimmed, "") }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = quantityPattern.firstMatch(in: trimmed, range: range),
              match.numberOfRanges == 2,
              let amountRange = Range(match.range(at: 1), in: trimmed) else {
            return (trimmed, "")
        }

        let amount = String(trimmed[amountRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !amount.isEmpty else {
            return (trimmed, "")
        }
        return (amount, "")
    }
}
