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
}
