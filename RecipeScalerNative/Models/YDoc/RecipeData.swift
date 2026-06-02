import Foundation

/// Full recipe data from a recipe Y.Doc.
/// Read from `Y.Map('recipe')` in document `{userId}:recipe:{recipeId}`.
struct RecipeData: Identifiable, Sendable {
    let id: String
    let name: String
    let servings: Int
    let color: String
    let version: String
    let description: String?
    let ingredients: [IngredientData]
    let nutrition: NutritionData?
    let isPublic: Bool
    let hasSteps: Bool
    let createdAt: String
    let updatedAt: String
    let imageUrl: String?
    let imageAspectRatio: Double?
    let originalRecipeLink: String?
    let originalRecipe: String?

    /// Recipe version enum for version-aware parsing.
    enum RecipeVersion: String, Sendable {
        case v1, v2, v3

        /// Detect version from the version string in Y.Doc. Defaults to v1 if absent.
        static func detect(_ versionString: String?) -> RecipeVersion {
            guard let v = versionString else { return .v1 }
            if let parsed = RecipeVersion(rawValue: v) {
                return parsed
            }
            // Legacy/native snapshots may store "3" instead of "v3".
            if v == "3" { return .v3 }
            if v == "2" { return .v2 }
            if v == "1" { return .v1 }
            return .v1
        }
    }

    func replacing(
        name: String? = nil,
        servings: Int? = nil,
        color: String? = nil,
        isPublic: Bool? = nil,
        description: String?? = nil,
        imageUrl: String?? = nil,
        ingredients: [IngredientData]? = nil,
        nutrition: NutritionData?? = nil
    ) -> RecipeData {
        RecipeData(
            id: id,
            name: name ?? self.name,
            servings: servings ?? self.servings,
            color: color ?? self.color,
            version: version,
            description: description ?? self.description,
            ingredients: ingredients ?? self.ingredients,
            nutrition: nutrition ?? self.nutrition,
            isPublic: isPublic ?? self.isPublic,
            hasSteps: hasSteps,
            createdAt: createdAt,
            updatedAt: updatedAt,
            imageUrl: imageUrl ?? self.imageUrl,
            imageAspectRatio: imageAspectRatio,
            originalRecipeLink: originalRecipeLink,
            originalRecipe: originalRecipe
        )
    }
}
