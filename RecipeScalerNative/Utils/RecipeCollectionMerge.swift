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

    /// Collection wins when recipe color empty or collection `updatedAt` is newer (cross-doc sync).
    private static func resolvedColor(recipe: RecipeData, entry: CollectionEntry) -> String {
        let recipeColor = recipe.color.trimmingCharacters(in: .whitespacesAndNewlines)
        if recipeColor.isEmpty { return entry.color }
        if isCollectionNewer(recipe: recipe, entry: entry) {
            let normalizedRecipe = RecipeAccentColor.normalizedStored(recipe.color)
            let normalizedEntry = RecipeAccentColor.normalizedStored(entry.color)
            if normalizedRecipe != normalizedEntry { return entry.color }
        }
        return recipe.color
    }

    private static func resolvedImageUrl(recipe: RecipeData, entry: CollectionEntry) -> String? {
        if let recipeUrl = recipe.imageUrl, !recipeUrl.isEmpty { return recipeUrl }
        return entry.imageUrl
    }

    private static func isCollectionNewer(recipe: RecipeData, entry: CollectionEntry) -> Bool {
        guard !entry.updatedAt.isEmpty else { return false }
        guard !recipe.updatedAt.isEmpty else { return true }
        return entry.updatedAt >= recipe.updatedAt
    }
}