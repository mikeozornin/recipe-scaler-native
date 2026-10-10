import Foundation

/// Lightweight recipe projection for list search and Spotlight-style indexing.
/// Avoids full `RecipeData` + XmlFragment→HTML conversion.
struct RecipeSearchIndex: Sendable, Equatable {
    let id: String
    /// Ingredient display names (separators excluded), parallel to `ingredientAmounts`.
    let ingredientNames: [String]
    /// Original/scaled amount strings for snippet display; empty when no quantity.
    let ingredientAmounts: [String]
    let descriptionPlainText: String
    /// `normalizeForSearch` of the fields above, computed once where the index is
    /// built (off the main actor) instead of on every keystroke for every recipe.
    let normalizedIngredientNames: [String]
    let normalizedDescription: String

    init(id: String, ingredientNames: [String], ingredientAmounts: [String], descriptionPlainText: String) {
        self.id = id
        self.ingredientNames = ingredientNames
        self.ingredientAmounts = ingredientAmounts
        self.descriptionPlainText = descriptionPlainText
        self.normalizedIngredientNames = ingredientNames.map(RecipeSearchUtils.normalizeForSearch)
        self.normalizedDescription = RecipeSearchUtils.normalizeForSearch(descriptionPlainText)
    }
}
