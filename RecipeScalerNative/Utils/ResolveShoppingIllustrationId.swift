//
//  ResolveShoppingIllustrationId.swift
//  RecipeScalerNative
//

import RecipeScalerCore

/// Display-time illustration id for shopping rows (parity with web `resolveShoppingItemIllustrationId`).
enum ResolveShoppingIllustrationId {
    static func resolve(item: ShoppingListItem) -> String? {
        if let stored = item.illustrationId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            return stored
        }
        return IngredientIllustrationNameMatcher.match(rawName: item.label)
    }
}
