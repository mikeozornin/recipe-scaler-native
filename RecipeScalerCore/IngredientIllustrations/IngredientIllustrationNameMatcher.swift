import Foundation

/// Deterministic name → catalog id (parity with web `matchIngredientNameToCatalog`).
public enum IngredientIllustrationNameMatcher {
    private static let minAliasLenForSubstring = 3

    public static func match(rawName: String, catalog: IngredientIllustrationCatalog = .shared) -> String? {
        let trimmedQuery = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        let normalizedQuery = IngredientIllustrationSearchNormalization.normalizeForSearch(trimmedQuery)
        guard !normalizedQuery.isEmpty else { return nil }

        let index = catalog.aliasIndexForMatching()

        for alias in index where alias.normalized == normalizedQuery {
            return alias.id
        }

        for alias in index where alias.normalized.count >= minAliasLenForSubstring
            && normalizedQuery.contains(alias.normalized) {
            return alias.id
        }

        let tokens = IngredientIllustrationSearchNormalization.tokenizeQuery(trimmedQuery)
        guard !tokens.isEmpty else { return nil }

        for alias in index where alias.normalized.count >= minAliasLenForSubstring
            && tokens.allSatisfy({ alias.normalized.contains($0) }) {
            return alias.id
        }

        return nil
    }
}