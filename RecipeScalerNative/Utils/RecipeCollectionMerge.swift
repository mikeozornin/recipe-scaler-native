import Foundation

/// Merges collection entry metadata into recipe display (web `use-yjs-sync` parity).
enum RecipeCollectionMerge {
    static func merged(_ recipe: RecipeData, with entry: CollectionEntry?) -> RecipeData {
        guard let entry else { return recipe }

        let name = resolvedName(recipe: recipe, entry: entry)
        let color = resolvedColor(recipe: recipe, entry: entry)
        let imageUrl = resolvedImageUrl(recipe: recipe, entry: entry)

        return recipe.replacing(name: name, color: color, imageUrl: imageUrl)
    }

    /// Recipe name when non-empty; otherwise collection (web observer path).
    private static func resolvedName(recipe: RecipeData, entry: CollectionEntry) -> String {
        let trimmed = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return recipe.name }
        return entry.name
    }

    /// Recipe doc is source of truth when color is set (web `use-yjs-sync` detail path).
    /// Collection is fallback only when the recipe map has no color.
    private static func resolvedColor(recipe: RecipeData, entry: CollectionEntry) -> String {
        let recipeColor = recipe.color.trimmingCharacters(in: .whitespacesAndNewlines)
        if !recipeColor.isEmpty { return recipe.color }
        return entry.color
    }

    private static func resolvedImageUrl(recipe: RecipeData, entry: CollectionEntry) -> String? {
        if let recipeUrl = recipe.imageUrl, !recipeUrl.isEmpty { return recipeUrl }
        return entry.imageUrl
    }

}