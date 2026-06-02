//
//  DocumentManager+ShoppingList.swift
//  RecipeScalerNative
//

import Foundation
import YrsC

extension DocumentManager {
    func shoppingDocKey(userId: String) -> String {
        "\(userId):shoppingList"
    }

    func readShoppingListSnapshot() async throws -> ShoppingListSnapshot {
        guard let userId = getCurrentUserId() else {
            return .empty
        }
        let key = shoppingDocKey(userId: userId)
        let doc = try await getOrCreateDoc(key: key)
        return try await doc.withReadTransaction { rawDoc, txn in
            guard let rootBranch = ymap(rawDoc, ShoppingListConstants.rootMapKey) else {
                return ShoppingListSnapshot.empty
            }
            let root = YrsMap(branch: rootBranch)
            let items = readShoppingItems(from: root, txn: txn)
            let meta = readShoppingMeta(from: root, txn: txn)
            return ShoppingListSnapshot(items: items, meta: meta)
        }
    }

    func setShoppingSortMode(_ mode: ShoppingSortMode) async throws {
        try await mutateShopping { _, meta, txn in
            meta.insert(key: "sortMode", value: .string(mode.rawValue), txn: txn)
        }
        await deliverPendingShoppingUpdate()
    }

    func setShoppingItemPurchased(id: String, purchased: Bool) async throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try await mutateShopping { items, _, txn in
            guard let index = shoppingItemIndex(items: items, id: id, txn: txn) else { return }
            items.withMap(at: index, txn: txn) { map in
                map.insert(key: "purchased", value: .bool(purchased), txn: txn)
                if purchased {
                    map.insert(key: "purchasedAt", value: .int(now), txn: txn)
                } else {
                    _ = map.remove(key: "purchasedAt", txn: txn)
                }
            }
        }
        await deliverPendingShoppingUpdate()
    }

    func addShoppingItems(_ newItems: [ShoppingListItem]) async throws {
        guard !newItems.isEmpty else { return }
        try await mutateShopping { items, _, txn in
            for item in newItems {
                let index = items.length(txn: txn)
                items.insert(value: .map([]), at: index, txn: txn)
                items.withMap(at: index, txn: txn) { map in
                    writeShoppingItem(map, item: item, txn: txn)
                }
            }
        }
        await deliverPendingShoppingUpdate()
    }

    func addManualShoppingItem(label: String) async throws {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = ShoppingListItem(
            label: trimmed,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        try await addShoppingItems([item])
    }

    func removeShoppingItem(id: String) async throws {
        try await mutateShopping { items, _, txn in
            guard let index = shoppingItemIndex(items: items, id: id, txn: txn) else { return }
            items.remove(at: index, txn: txn)
        }
        await deliverPendingShoppingUpdate()
    }

    // MARK: - Private

    private func mutateShopping(
        _ body: (YrsArray, YrsMap, OpaquePointer) throws -> Void
    ) async throws {
        guard let userId = getCurrentUserId() else {
            throw RecipeEditError.documentNotLoaded
        }
        let key = shoppingDocKey(userId: userId)
        let doc = try await getOrCreateDoc(key: key)
        try await doc.withWriteTransaction { rawDoc, txn in
            guard let rootBranch = ymap(rawDoc, ShoppingListConstants.rootMapKey) else {
                throw RecipeEditError.documentNotLoaded
            }
            let root = YrsMap(branch: rootBranch)
            try ensureShoppingStructure(root: root, txn: txn)
            let items = try shoppingItemsArray(root: root, txn: txn)
            let meta = try shoppingMetaMap(root: root, txn: txn)
            try body(items, meta, txn)
        }
        onShoppingChanged?()
    }

    private func ensureShoppingStructure(root: YrsMap, txn: OpaquePointer) throws {
        if root.isNullOrMissing(key: ShoppingListConstants.itemsKey, txn: txn) {
            root.insert(key: ShoppingListConstants.itemsKey, value: .yarray([]), txn: txn)
        }
        if root.isNullOrMissing(key: ShoppingListConstants.metaKey, txn: txn) {
            let metaFields: [(String, YrsInput)] = [
                ("sortMode", .string(ShoppingSortMode.recipe.rawValue)),
                ("schemaVersion", .int(1)),
            ]
            root.insert(key: ShoppingListConstants.metaKey, value: .map(metaFields), txn: txn)
        }
    }

    private func shoppingItemsArray(root: YrsMap, txn: OpaquePointer) throws -> YrsArray {
        guard let array = try root.withNestedArray(key: ShoppingListConstants.itemsKey, txn: txn, { $0 }) else {
            throw RecipeEditError.documentNotLoaded
        }
        return array
    }

    private func shoppingMetaMap(root: YrsMap, txn: OpaquePointer) throws -> YrsMap {
        guard let meta = try root.withNestedMap(key: ShoppingListConstants.metaKey, txn: txn, { $0 }) else {
            throw RecipeEditError.documentNotLoaded
        }
        return meta
    }

    private func shoppingItemIndex(items: YrsArray, id: String, txn: OpaquePointer) -> UInt32? {
        let len = items.length(txn: txn)
        for index in 0..<len {
            let matches = items.withMap(at: index, txn: txn) { map -> Bool in
                map.scalarString(key: "id", txn: txn) == id
            }
            if matches == true { return index }
        }
        return nil
    }

    private func writeShoppingItem(_ map: YrsMap, item: ShoppingListItem, txn: OpaquePointer) {
        map.insert(key: "id", value: .string(item.id), txn: txn)
        map.insert(key: "label", value: .string(item.label), txn: txn)
        map.insert(key: "purchased", value: .bool(item.purchased), txn: txn)
        if let recipeId = item.recipeId {
            map.insert(key: "recipeId", value: .string(recipeId), txn: txn)
        }
        if let ingredientId = item.ingredientId {
            map.insert(key: "ingredientId", value: .string(ingredientId), txn: txn)
        }
        if !item.recipeName.isEmpty {
            map.insert(key: "recipeName", value: .string(item.recipeName), txn: txn)
        }
        if let purchasedAt = item.purchasedAt {
            map.insert(key: "purchasedAt", value: .int(purchasedAt), txn: txn)
        }
        if let createdAt = item.createdAt {
            map.insert(key: "createdAt", value: .int(createdAt), txn: txn)
        }
    }

    private func readShoppingItems(from root: YrsMap, txn: OpaquePointer) -> [ShoppingListItem] {
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

    private func readShoppingMeta(from root: YrsMap, txn: OpaquePointer) -> ShoppingListMeta {
        guard let metaMap = try? root.withNestedMap(key: ShoppingListConstants.metaKey, txn: txn, { $0 }) else {
            return .default
        }
        let sortRaw = metaMap.scalarString(key: "sortMode", txn: txn)
        let sort: ShoppingSortMode = sortRaw == ShoppingSortMode.alphabet.rawValue ? .alphabet : .recipe
        let version = metaMap.int(key: "schemaVersion", txn: txn) ?? 1
        return ShoppingListMeta(sortMode: sort, schemaVersion: version)
    }

    private func deliverPendingShoppingUpdate() async {
        guard let handler = onLocalShoppingUpdate,
              let userId = getCurrentUserId() else { return }
        let key = shoppingDocKey(userId: userId)
        guard let doc = getDoc(key: key),
              let update = await doc.encodeStateAsUpdate(),
              !update.isEmpty else { return }
        await handler(update)
    }
}