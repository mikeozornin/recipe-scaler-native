//
//  LayoutPreferencesStore.swift
//  RecipeScalerNative
//
//  Spec 043 — persisted split column widths.
//

import Foundation

@MainActor
enum LayoutPreferencesStore {
    private enum Keys {
        static let recipeListWidth = "layout.recipe-list-width"
        static let recipeIngredientsWidth = "layout.recipe-ingredients-width"
        static let lastRecipesRoute = "layout.last-recipes-route"
    }

    static let recipeListWidthDefault: Double = 320
    static let recipeListWidthMin: Double = 280
    static let recipeListWidthMax: Double = 480
    static let recipeIngredientsWidthDefault: Double = 400
    static let recipeIngredientsWidthMin: Double = 280
    static let recipeIngredientsWidthMax: Double = 640

    static var recipeListWidth: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: Keys.recipeListWidth)
            if stored == 0 { return recipeListWidthDefault }
            return clamp(
                stored,
                min: recipeListWidthMin,
                max: recipeListWidthMax,
                defaultValue: recipeListWidthDefault
            )
        }
        set {
            UserDefaults.standard.set(
                clamp(
                    newValue,
                    min: recipeListWidthMin,
                    max: recipeListWidthMax,
                    defaultValue: recipeListWidthDefault
                ),
                forKey: Keys.recipeListWidth
            )
        }
    }

    static var recipeIngredientsWidth: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: Keys.recipeIngredientsWidth)
            if stored == 0 { return recipeIngredientsWidthDefault }
            return clamp(
                stored,
                min: recipeIngredientsWidthMin,
                max: recipeIngredientsWidthMax,
                defaultValue: recipeIngredientsWidthDefault
            )
        }
        set {
            UserDefaults.standard.set(
                clamp(
                    newValue,
                    min: recipeIngredientsWidthMin,
                    max: recipeIngredientsWidthMax,
                    defaultValue: recipeIngredientsWidthDefault
                ),
                forKey: Keys.recipeIngredientsWidth
            )
        }
    }

    static var lastRecipesRoute: String {
        get { UserDefaults.standard.string(forKey: Keys.lastRecipesRoute) ?? "/" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastRecipesRoute) }
    }

    private static func clamp(
        _ value: Double,
        min minimum: Double,
        max maximum: Double,
        defaultValue: Double
    ) -> Double {
        guard value.isFinite else { return defaultValue }
        return Swift.min(Swift.max(value, minimum), maximum)
    }
}
