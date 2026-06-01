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
            return RecipeVersion(rawValue: v) ?? .v1
        }
    }
}
