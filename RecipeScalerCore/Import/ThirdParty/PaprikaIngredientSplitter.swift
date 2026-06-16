//
//  PaprikaIngredientSplitter.swift
//  RecipeScalerCore
//

import Foundation

enum PaprikaIngredientSplitter {
    private static let quantityPattern = try! NSRegularExpression(
        pattern: #"^([\d.,/\s]+(?:g|kg|ml|l|oz|lb|cup|cups|tbsp|tsp|шт\.?)?)\s+(.+)$"#,
        options: [.caseInsensitive]
    )

    static func split(line: String) -> (amount: String, name: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }

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
