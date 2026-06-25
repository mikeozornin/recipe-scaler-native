//
//  ShoppingListReader.swift
//  RecipeScalerNative
//

import Foundation
import YrsC

/// Stateless reader for shopping-list Yjs documents.
enum ShoppingListReader {
    static func readItems(from root: YrsMap, txn: OpaquePointer) -> [ShoppingListItem] {
        guard let itemsArray = try? root.withNestedArray(key: ShoppingListConstants.itemsKey, txn: txn, { $0 }) else {
            return []
        }
        var items: [ShoppingListItem] = []
        itemsArray.forEachMap(txn: txn) { map in
            guard let id = map.scalarString(key: "id", txn: txn), !id.isEmpty else { return }
            items.append(
                ShoppingListItem(
                    id: id,
                    label: map.scalarString(key: "label", txn: txn) ?? "",
                    recipeId: map.scalarString(key: "recipeId", txn: txn),
                    ingredientId: map.scalarString(key: "ingredientId", txn: txn),
                    recipeName: map.scalarString(key: "recipeName", txn: txn) ?? "",
                    purchased: map.bool(key: "purchased", txn: txn) ?? false,
                    purchasedAt: map.int(key: "purchasedAt", txn: txn).map { Int64($0) },
                    createdAt: map.int(key: "createdAt", txn: txn).map { Int64($0) }
                )
            )
        }
        return items
    }

    static func readMeta(from root: YrsMap, txn: OpaquePointer) -> ShoppingListMeta {
        guard let metaMap = try? root.withNestedMap(key: ShoppingListConstants.metaKey, txn: txn, { $0 }) else {
            return .default
        }
        let sortRaw = metaMap.scalarString(key: "sortMode", txn: txn)
        let sort: ShoppingSortMode = sortRaw == ShoppingSortMode.alphabet.rawValue ? .alphabet : .recipe
        let version = metaMap.int(key: "schemaVersion", txn: txn) ?? 1
        return ShoppingListMeta(sortMode: sort, schemaVersion: version)
    }
}
