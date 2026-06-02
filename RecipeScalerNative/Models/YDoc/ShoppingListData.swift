//
//  ShoppingListData.swift
//  RecipeScalerNative
//

import Foundation

struct ShoppingListItem: Identifiable, Equatable, Sendable {
    let id: String
    var label: String
    var recipeId: String?
    var ingredientId: String?
    var recipeName: String
    var purchased: Bool
    var purchasedAt: Int64?
    var createdAt: Int64?

    init(
        id: String = UUID().uuidString,
        label: String,
        recipeId: String? = nil,
        ingredientId: String? = nil,
        recipeName: String = "",
        purchased: Bool = false,
        purchasedAt: Int64? = nil,
        createdAt: Int64? = nil
    ) {
        self.id = id
        self.label = label
        self.recipeId = recipeId
        self.ingredientId = ingredientId
        self.recipeName = recipeName
        self.purchased = purchased
        self.purchasedAt = purchasedAt
        self.createdAt = createdAt
    }
}

struct ShoppingListMeta: Equatable, Sendable {
    var sortMode: ShoppingSortMode
    var schemaVersion: Int

    static let `default` = ShoppingListMeta(sortMode: .recipe, schemaVersion: 1)
}

struct ShoppingListSnapshot: Equatable, Sendable {
    var items: [ShoppingListItem]
    var meta: ShoppingListMeta

    static let empty = ShoppingListSnapshot(items: [], meta: .default)
}