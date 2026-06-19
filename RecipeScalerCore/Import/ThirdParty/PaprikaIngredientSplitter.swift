//
//  PaprikaIngredientSplitter.swift
//  RecipeScalerCore
//

import Foundation

enum PaprikaIngredientSplitter {
    /// MIK-145 [review #62]: no unit recognition — only the leading numeric
    /// token is extracted into `amount`; everything after it goes to `name`
    /// verbatim. The splitter no longer recognizes a fixed set of units
    /// (g/kg/ml/cups/tbsp/…), so the unit field is always empty here.
    //
    // MIK-143 [review #59]: safe static-init — `try?` + nil-guard in consumer.
    private static let quantityPattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^([\d.,/\s]+)\s+(.+)$"#
    )

    static func split(line: String) -> (amount: String, name: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }
        guard let quantityPattern else { return ("", trimmed) }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if let match = quantityPattern.firstMatch(in: trimmed, range: range),
           match.numberOfRanges == 3,
           let amountRange = Range(match.range(at: 1), in: trimmed),
           let nameRange = Range(match.range(at: 2), in: trimmed) {
            let amount = String(trimmed[amountRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String(trimmed[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return (amount, name)
            }
        }

        return ("", trimmed)
    }
}
