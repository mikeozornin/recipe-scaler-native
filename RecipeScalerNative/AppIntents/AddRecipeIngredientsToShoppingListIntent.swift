//
//  AddRecipeIngredientsToShoppingListIntent.swift
//  RecipeScalerNative
//

import AppIntents

struct AddRecipeIngredientsToShoppingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Add recipe ingredients to shopping list"
    static var description = IntentDescription("Adds all ingredients from a recipe to your shopping list.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Recipe")
    var recipe: RecipeEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        ShoppingIntentActionQueue.enqueue(.addRecipeIngredients(recipeId: recipe.id))
        return .result(dialog: "Adding ingredients from \(recipe.name) to your shopping list.")
    }
}
