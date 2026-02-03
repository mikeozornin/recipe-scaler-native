import Foundation
import SwiftData
@testable import RecipeScalerNative

enum TestSupport {
    static func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Recipe.self,
            Ingredient.self,
            RecipeTimer.self,
            ApiCacheEntry.self,
            configurations: config
        )
    }

    static func seedRecipes(into context: ModelContext) {
        let ingredients = [
            Ingredient(name: "Eggs", originalAmount: 2, unit: "pcs", order: 0),
            Ingredient(name: "Tomatoes", originalAmount: 200, unit: "g", order: 1),
            Ingredient(name: "Salt", originalAmount: 1, unit: "tsp", order: 2)
        ]

        let recipe = Recipe(
            name: "Shakshuka",
            recipeDescription: "<p>Simmer and serve</p>",
            color: "#FF6B35",
            scaleFactor: 1.0,
            ingredients: ingredients
        )

        context.insert(recipe)
        try? context.save()
    }

    static func sampleRecipe() -> Recipe {
        let ingredients = [
            Ingredient(name: "Flour", originalAmount: 200, unit: "g", order: 0),
            Ingredient(name: "Water", originalAmount: 120, unit: "ml", order: 1),
            Ingredient(name: "Yeast", originalAmount: 5, unit: "g", order: 2)
        ]

        return Recipe(
            name: "Quick Flatbread",
            recipeDescription: "<p>Mix, rest, and cook on a hot pan.</p>",
            originalRecipeLink: "https://example.com/flatbread",
            color: "#4C9F70",
            scaleFactor: 1.0,
            ingredients: ingredients
        )
    }
}
