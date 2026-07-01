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
    static let recipeIngredientsWidthDefault: Double = 400

    static var recipeListWidth: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: Keys.recipeListWidth)
            if stored == 0 { return recipeListWidthDefault }
            return max(recipeListWidthMin, stored)
        }
        set {
            UserDefaults.standard.set(max(recipeListWidthMin, newValue), forKey: Keys.recipeListWidth)
        }
    }

    static var recipeIngredientsWidth: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: Keys.recipeIngredientsWidth)
            if stored == 0 { return recipeIngredientsWidthDefault }
            return stored
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.recipeIngredientsWidth)
        }
    }

    static var lastRecipesRoute: String {
        get { UserDefaults.standard.string(forKey: Keys.lastRecipesRoute) ?? "/" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastRecipesRoute) }
    }
}