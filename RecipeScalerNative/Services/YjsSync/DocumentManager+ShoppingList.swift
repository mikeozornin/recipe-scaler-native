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
        return try await doc.withReadTransaction { _, txn in
            guard let rootBranch = ytype_get(txn, ShoppingListConstants.rootMapKey) else {
                return ShoppingListSnapshot.empty
            }
            let root = YrsMap(branch: rootBranch)
            let items = ShoppingListReader.readItems(from: root, txn: txn)
            let meta = ShoppingListReader.readMeta(from: root, txn: txn)
            return ShoppingListSnapshot(items: items, meta: meta)
        }
    }

    func setShoppingSortMode(_ mode: ShoppingSortMode) async throws {
        let key = try await mutateShoppingItems { _, meta, txn in
            meta.insert(key: "sortMode", value: .string(mode.rawValue), txn: txn)
        }
        await persistSnapshot(docKey: key)
        await deliverPendingShoppingUpdate()
    }

    func setShoppingItemPurchased(id: String, purchased: Bool) async throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let key = try await mutateShoppingItems { items, _, txn in
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
        await persistSnapshot(docKey: key)
        await deliverPendingShoppingUpdate()
    }

    func addShoppingItems(_ newItems: [ShoppingListItem]) async throws {
        guard !newItems.isEmpty else { return }
        let key = try await mutateShoppingItems { items, _, txn in
            for item in newItems {
                let index = items.length(txn: txn)
                items.insert(value: .map([]), at: index, txn: txn)
                items.withMap(at: index, txn: txn) { map in
                    writeShoppingItem(map, item: item, txn: txn)
                }
            }
        }
        await persistSnapshot(docKey: key)
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
        let key = try await mutateShoppingItems { items, _, txn in
            guard let index = shoppingItemIndex(items: items, id: id, txn: txn) else { return }
            items.remove(at: index, txn: txn)
        }
        await persistSnapshot(docKey: key)
        await deliverPendingShoppingUpdate()
    }

    func updateShoppingItemLabel(id: String, label: String) async throws {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try await removeShoppingItem(id: id)
            return
        }
        let key = try await mutateShoppingItems { items, _, txn in
            guard let index = shoppingItemIndex(items: items, id: id, txn: txn) else { return }
            items.withMap(at: index, txn: txn) { map in
                map.insert(key: "label", value: .string(trimmed), txn: txn)
            }
        }
        await persistSnapshot(docKey: key)
        await deliverPendingShoppingUpdate()
    }

    func clearPurchasedShoppingItems() async throws {
        let key = try await mutateShoppingItems { items, _, txn in
            let count = items.length(txn: txn)
            guard count > 0 else { return }
            for index in stride(from: Int(count) - 1, through: 0, by: -1) {
                let purchased = items.withMap(at: UInt32(index), txn: txn) { map in
                    map.bool(key: "purchased", txn: txn) ?? false
                }
                if purchased == true {
                    items.remove(at: UInt32(index), txn: txn)
                }
            }
        }
        await persistSnapshot(docKey: key)
        await deliverPendingShoppingUpdate()
    }

    /// Replace the entire shopping list (store screenshot seed).
    ///
    /// DEBUG-only: the single call site is `DebugLaunchOptions.applyScreenshotShoppingSeedIfNeeded`,
    /// which is itself `#if DEBUG`-gated. Bypasses the normal CRDT-aware
    /// mutation path that other shopping operations go through, so it must
    /// not ship in Release.
    #if DEBUG
    func replaceShoppingItems(_ newItems: [ShoppingListItem]) async throws {
        let key = try await mutateShoppingItems { items, _, txn in
            let count = items.length(txn: txn)
            if count > 0 {
                for index in stride(from: Int(count) - 1, through: 0, by: -1) {
                    items.remove(at: UInt32(index), txn: txn)
                }
            }
            for item in newItems {
                let index = items.length(txn: txn)
                items.insert(value: .map([]), at: index, txn: txn)
                items.withMap(at: index, txn: txn) { map in
                    writeShoppingItem(map, item: item, txn: txn)
                }
            }
        }
        await persistSnapshot(docKey: key)
        await deliverPendingShoppingUpdate()
    }
    #endif

    // MARK: - Private

    @discardableResult
    private func mutateShoppingItems(
        _ body: (YrsArray, YrsMap, OpaquePointer) throws -> Void
    ) async throws -> String {
        guard let userId = getCurrentUserId() else {
            throw RecipeEditError.documentNotLoaded
        }
        let key = shoppingDocKey(userId: userId)
        guard let context = updateContext(docKey: key, recipeId: nil) else {
            throw RecipeEditError.documentNotLoaded
        }
        let doc = try await getOrCreateDoc(key: key)
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
        try await doc.withWriteTransaction { _, txn in
            guard let rootBranch = ytype_get(txn, ShoppingListConstants.rootMapKey) else {
                throw RecipeEditError.documentNotLoaded
            }
            let root = YrsMap(branch: rootBranch)
            try ensureShoppingStructure(root: root, txn: txn)
            let items = try shoppingItemsArray(root: root, txn: txn)
            let meta = try shoppingMetaMap(root: root, txn: txn)
            try body(items, meta, txn)
        }
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
        onShoppingChanged?(context)
        return key
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

    private func deliverPendingShoppingUpdate() async {
        guard let handler = onLocalShoppingUpdate,
              let userId = getCurrentUserId() else { return }
        let key = shoppingDocKey(userId: userId)
        guard let context = updateContext(docKey: key, recipeId: nil) else { return }
        guard let doc = getDoc(key: key) else { return }
        var update = await doc.consumePendingLocalUpdates()
        if update == nil || update?.isEmpty == true {
            update = await doc.encodeStateAsUpdate()
        }
        guard let update, !update.isEmpty else { return }
        // Do not await: handler hops to @MainActor YjsSyncService while caller may be blocked on this actor.
        Task { await handler(context, update) }
    }
}
