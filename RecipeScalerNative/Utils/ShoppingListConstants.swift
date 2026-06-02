//
//  ShoppingListConstants.swift
//  RecipeScalerNative
//

import Foundation

enum ShoppingListConstants {
    static let rootMapKey = "shopping"
    static let itemsKey = "items"
    static let metaKey = "meta"
    /// Socket/offline recipe id sentinel (matches web `OFFLINE_RECIPE_ID_SHOPPING_LIST`).
    static let offlineRecipeId = "__rs_shopping_list__"
    static let documentKind = "shoppingList"
}

enum ShoppingSortMode: String, CaseIterable, Sendable {
    case recipe
    case alphabet
}