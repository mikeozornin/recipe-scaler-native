//
//  OpenRecipeIntent.swift
//  RecipeScalerNative
//

import AppIntents

struct OpenRecipeIntent: AppIntent {
    static var title: LocalizedStringResource = "Open a recipe"
    static var description = IntentDescription("Opens a recipe in Recipe Scaler.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Recipe")
    var recipe: RecipeEntity

    func perform() async throws -> some IntentResult {
        await DeepLinkRouter.shared.handle(.openRecipe(recipeId: recipe.id))
        return .result()
    }
}
