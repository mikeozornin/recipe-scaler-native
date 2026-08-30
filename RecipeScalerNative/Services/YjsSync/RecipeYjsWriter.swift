//
//  RecipeYjsWriter.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

/// Stateless writers and typed writer-structs for mutating Yjs recipe documents.
///
/// `DocumentManager` opens the write transaction (`YrsDocument.withWriteTransaction`)
/// and constructs a `RecipeMapWriter` / `CollectionEntryWriter` / `FolderEntryWriter`
/// inside it. Callers never touch a raw `YrsMap` or `OpaquePointer` — the FFI
/// surface stays inside `YrsDocument` actor's transaction boundary.
///
/// The static helpers in `RecipeYjsWriter` are pure functions over `YrsMap` /
/// `YrsArray` + the live transaction pointer (no actor state, no caches), so
/// they live outside `DocumentManager` (same rationale as `RecipeYjsCodec`).
enum RecipeYjsWriter {

    // MARK: - Ingredient array helpers

    /// Mutate `ingredients` while the parent `YOutput` from `ymap_get` stays alive (see `withNestedArray`).
    static func withIngredientsArray<T>(
        in recipeMap: YrsMap,
        txn: OpaquePointer,
        _ body: (YrsArray) throws -> T
    ) throws -> T {
        if recipeMap.isNullOrMissing(key: "ingredients", txn: txn) {
            recipeMap.insert(key: "ingredients", value: .yarray([]), txn: txn)
        }
        guard let result = try recipeMap.withNestedArray(key: "ingredients", txn: txn, body) else {
            throw RecipeEditError.documentNotLoaded
        }
        return result
    }

    /// Inserts a new ingredient map via scalar `ymap_insert` calls (avoids nested `yinput_ymap` UTF-8 panic in yffi).
    static func appendIngredient(
        _ ingredient: IngredientData,
        to array: YrsArray,
        txn: OpaquePointer
    ) throws {
        let index = array.length(txn: txn)
        try insertIngredient(ingredient, into: array, at: index, txn: txn)
    }

    static func insertIngredient(
        _ ingredient: IngredientData,
        into array: YrsArray,
        at index: UInt32,
        txn: OpaquePointer
    ) throws {
        array.insert(value: .map([]), at: index, txn: txn)
        let wrote = array.withMap(at: index, txn: txn) { ingMap -> Bool in
            writeIngredient(ingMap, ingredient: ingredient, txn: txn)
            return true
        }
        guard wrote == true else {
            throw RecipeEditError.documentNotLoaded
        }
    }

    static func renumberIngredientOrders(in array: YrsArray, txn: OpaquePointer) {
        let len = array.length(txn: txn)
        for index in 0..<len {
            array.withMap(at: index, txn: txn) { ingMap in
                // Match web: ingMap.set('order', index + 1) → Y_JSON_NUM (not int, which becomes BigInt in JS).
                ingMap.insert(key: "order", value: .double(Double(index + 1)), txn: txn)
            }
        }
    }

    static func writeIngredient(_ ingMap: YrsMap, ingredient: IngredientData, txn: OpaquePointer) {
        ingMap.insert(key: "id", value: .string(ingredient.id), txn: txn)
        ingMap.insert(key: "name", value: .string(ingredient.name), txn: txn)
        // Web parity: order is stored as Y_JSON_NUM (matches ingMap.set('order', n)).
        ingMap.insert(key: "order", value: .double(Double(ingredient.order)), txn: txn)
        ingMap.insert(key: "isSeparator", value: .bool(ingredient.isSeparator), txn: txn)
        ingMap.insert(key: "unit", value: .string(ingredient.unit), txn: txn)

        if ingredient.hasQuantity, let numeric = Double(ingredient.originalAmount.replacingOccurrences(of: ",", with: ".")) {
            ingMap.insert(key: "originalAmount", value: .double(numeric), txn: txn)
            ingMap.insert(key: "amount", value: .double(numeric), txn: txn)
        } else if ingredient.hasQuantity {
            ingMap.insert(key: "originalAmount", value: .string(ingredient.originalAmount), txn: txn)
            ingMap.insert(key: "amount", value: .string(ingredient.amount.isEmpty ? ingredient.originalAmount : ingredient.amount), txn: txn)
        } else {
            ingMap.remove(key: "originalAmount", txn: txn)
            ingMap.insert(key: "amount", value: .string(""), txn: txn)
        }

        writeIllustrationBinding(ingMap, ingredient: ingredient, txn: txn)
        writeNutrition(ingMap, ingredient: ingredient, txn: txn)
    }

    static func writeIllustrationBinding(_ ingMap: YrsMap, ingredient: IngredientData, txn: OpaquePointer) {
        if let illustrationId = ingredient.illustrationId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !illustrationId.isEmpty {
            ingMap.insert(key: "illustrationId", value: .string(illustrationId), txn: txn)
        } else {
            ingMap.remove(key: "illustrationId", txn: txn)
        }
        if ingredient.illustrationPickerCleared {
            ingMap.insert(key: "illustrationPickerCleared", value: .bool(true), txn: txn)
        } else {
            ingMap.remove(key: "illustrationPickerCleared", txn: txn)
        }
    }

    /// Partial update for picker (does not rewrite name/qty/nutrition).
    static func applyIllustrationPickerBinding(
        to ingMap: YrsMap,
        illustrationId: String?,
        pickerCleared: Bool,
        txn: OpaquePointer
    ) {
        if let illustrationId = illustrationId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !illustrationId.isEmpty {
            ingMap.insert(key: "illustrationId", value: .string(illustrationId), txn: txn)
            ingMap.remove(key: "illustrationPickerCleared", txn: txn)
        } else {
            ingMap.remove(key: "illustrationId", txn: txn)
            if pickerCleared {
                ingMap.insert(key: "illustrationPickerCleared", value: .bool(true), txn: txn)
            } else {
                ingMap.remove(key: "illustrationPickerCleared", txn: txn)
            }
        }
    }

    static func writeNutrition(_ ingMap: YrsMap, ingredient: IngredientData, txn: OpaquePointer) {
        writeOptionalDouble(ingMap, key: "calories", value: ingredient.calories, txn: txn)
        writeOptionalDouble(ingMap, key: "protein", value: ingredient.protein, txn: txn)
        writeOptionalDouble(ingMap, key: "fat", value: ingredient.fat, txn: txn)
        writeOptionalDouble(ingMap, key: "carbs", value: ingredient.carbs, txn: txn)
        writeOptionalDouble(ingMap, key: "weight", value: ingredient.weight, txn: txn)
    }

    static func writeOptionalDouble(_ map: YrsMap, key: String, value: Double?, txn: OpaquePointer) {
        if let value {
            map.insert(key: key, value: .double(value), txn: txn)
        } else if !map.isNullOrMissing(key: key, txn: txn) {
            map.remove(key: key, txn: txn)
        }
    }

    /// Write the `folderIds` JSON-array value on a recipe entry map.
    /// Removes the key when the normalized list is empty (web `setRecipeFolderIds`).
    /// Important: this is a *replacement* of the whole array (last-write-wins per recipe).
    static func writeRecipeFolderIds(map: YrsMap, folderIds: [String], txn: OpaquePointer) {
        if folderIds.isEmpty {
            if map.hasJSONArray(key: RecipeFolderConstants.folderIdsKey, txn: txn) {
                _ = map.remove(key: RecipeFolderConstants.folderIdsKey, txn: txn)
            }
            return
        }
        map.insert(
            key: RecipeFolderConstants.folderIdsKey,
            value: .jsonStringArray(folderIds),
            txn: txn
        )
    }
}

/// Typed write-handle for the `recipe` Y.Map of a single recipe document.
///
/// Constructed inside `YrsDocument.withWriteTransaction` by `DocumentManager`;
/// never escapes the actor. `DocumentManager.mutateRecipe` bumps `updatedAt`
/// automatically after the body returns — callers must not write `updatedAt`.
struct RecipeMapWriter {
    let map: YrsMap
    let txn: OpaquePointer

    // MARK: - Scalar fields

    func setName(_ name: String) {
        map.insert(key: "name", value: .string(name), txn: txn)
    }

    func setServings(_ servings: Double) {
        // Web Yjs stores servings as JS number (float). Yrs `Y_JSON_INT` is not read by `normalizeServingsValue`.
        map.insert(key: "servings", value: .double(servings), txn: txn)
    }

    func setImageUrl(_ imageUrl: String) {
        map.insert(key: "imageUrl", value: .string(imageUrl), txn: txn)
    }

    func setImageAspectRatio(_ aspectRatio: Double) {
        map.insert(key: "imageAspectRatio", value: .double(aspectRatio), txn: txn)
    }

    func clearImageUrl() {
        _ = map.remove(key: "imageUrl", txn: txn)
        _ = map.remove(key: "imageAspectRatio", txn: txn)
    }

    func setColor(_ color: String) {
        map.insert(key: "color", value: .string(color), txn: txn)
    }

    func setIsPublic(_ isPublic: Bool) {
        map.insert(key: "isPublic", value: .bool(isPublic), txn: txn)
    }

    func setDescription(_ description: String) {
        map.insert(key: "description", value: .string(description), txn: txn)
    }

    func setHasSteps(_ hasSteps: Bool) {
        map.insert(key: "hasSteps", value: .bool(hasSteps), txn: txn)
    }

    func setOriginalRecipe(_ source: String) {
        map.insert(key: "originalRecipe", value: .string(source), txn: txn)
    }

    func setOriginalRecipeLink(_ link: String) {
        map.insert(key: "originalRecipeLink", value: .string(link), txn: txn)
    }

    func setCreatedAt(_ createdAt: String) {
        map.insert(key: "createdAt", value: .string(createdAt), txn: txn)
    }

    /// Used by import paths that preserve the original creation time (e.g. `applyNativeRecipe`).
    /// Note: the regular v3-only mutator already bumps `updatedAt` automatically — this method
    /// only applies the explicit value (it wins because it runs *before* the framework bump).
    func setUpdatedAt(_ updatedAt: String) {
        map.insert(key: "updatedAt", value: .string(updatedAt), txn: txn)
    }

    func setNutritionOutdated(_ outdated: Bool) {
        map.insert(key: "nutritionOutdated", value: .bool(outdated), txn: txn)
        writeNutritionMap(
            calories: nil,
            protein: nil,
            fat: nil,
            carbs: nil,
            nutritionOutdated: outdated
        )
    }

    /// Bulk-write a set of scalar fields via raw `YrsInput` values.
    /// Used by import / migration paths (e.g. `updateRecipeFields`) that compose
    /// arbitrary key/value pairs without per-field wrapper methods.
    func writeRawFields(_ fields: [(String, YrsInput)]) {
        for (key, value) in fields {
            map.insert(key: key, value: value, txn: txn)
        }
    }

    // MARK: - Nutrition (nested Y.Map)

    /// Write the four core nutrition fields under the nested `nutrition` Y.Map,
    /// creating it when missing. Matches the import parity of `applyNativeRecipe`
    /// and the partial-update semantics of `updateNutrition`.
    func writeNutritionMap(
        calories: Double?,
        protein: Double?,
        fat: Double?,
        carbs: Double?,
        totalWeight: Double? = nil,
        nutritionOutdated: Bool? = nil
    ) {
        var fields: [(String, YrsInput)] = []
        if let calories { fields.append(("calories", .double(calories))) }
        if let protein { fields.append(("protein", .double(protein))) }
        if let fat { fields.append(("fat", .double(fat))) }
        if let carbs { fields.append(("carbs", .double(carbs))) }
        if let totalWeight { fields.append(("totalWeight", .double(totalWeight))) }
        if let nutritionOutdated { fields.append(("nutritionOutdated", .bool(nutritionOutdated))) }
        guard !fields.isEmpty else { return }

        if map.isNullOrMissing(key: "nutrition", txn: txn) {
            map.insert(key: "nutrition", value: .map(fields), txn: txn)
        } else {
            map.withNestedMap(key: "nutrition", txn: txn) { nMap in
                for (key, value) in fields {
                    nMap.insert(key: key, value: value, txn: txn)
                }
            }
        }
    }

    // MARK: - Ingredients (Y.Array)

    func appendIngredient(_ ingredient: IngredientData) throws {
        try RecipeYjsWriter.withIngredientsArray(in: map, txn: txn) { array in
            try RecipeYjsWriter.appendIngredient(ingredient, to: array, txn: txn)
            RecipeYjsWriter.renumberIngredientOrders(in: array, txn: txn)
        }
    }

    func appendIngredients(_ ingredients: [IngredientData]) throws {
        try RecipeYjsWriter.withIngredientsArray(in: map, txn: txn) { array in
            for ingredient in ingredients {
                try RecipeYjsWriter.appendIngredient(ingredient, to: array, txn: txn)
            }
            RecipeYjsWriter.renumberIngredientOrders(in: array, txn: txn)
        }
    }

    /// Overwrite the ingredient map identified by `ingredient.id`, if present.
    /// No-op when the id does not match any existing element (parity with old
    /// `DocumentManager.updateIngredient`).
    func updateIngredient(_ ingredient: IngredientData, markNutritionOutdated: Bool = true) throws {
        try RecipeYjsWriter.withIngredientsArray(in: map, txn: txn) { array in
            let len = array.length(txn: txn)
            for index in 0..<len {
                array.withMap(at: index, txn: txn) { ingMap in
                    if ingMap.scalarString(key: "id", txn: txn) == ingredient.id {
                        RecipeYjsWriter.writeIngredient(ingMap, ingredient: ingredient, txn: txn)
                    }
                }
            }
        }
        if markNutritionOutdated {
            // Dual-write (root + nested): `readNutrition` reads the nested map
            // only on the v2/v3 path — a root-only write is invisible to it.
            setNutritionOutdated(true)
        }
    }

    func updateIngredientIllustrationBinding(
        ingredientId: String,
        illustrationId: String?,
        pickerCleared: Bool
    ) throws {
        try updateIngredientIllustrationBindings([
            (ingredientId: ingredientId, illustrationId: illustrationId, pickerCleared: pickerCleared, expectedName: nil),
        ])
    }

    /// Applies illustration bindings in a single write transaction.
    /// Skips rows whose `name` no longer matches `expectedName` (concurrent rename/delete guard).
    func updateIngredientIllustrationBindings(
        _ bindings: [(ingredientId: String, illustrationId: String?, pickerCleared: Bool, expectedName: String?)]
    ) throws {
        guard !bindings.isEmpty else { return }
        let byId = Dictionary(uniqueKeysWithValues: bindings.map { ($0.ingredientId, $0) })
        try RecipeYjsWriter.withIngredientsArray(in: map, txn: txn) { array in
            let len = array.length(txn: txn)
            for index in 0..<len {
                array.withMap(at: index, txn: txn) { ingMap in
                    guard let rowId = ingMap.scalarString(key: "id", txn: txn),
                          let binding = byId[rowId]
                    else { return }
                    if let expectedName = binding.expectedName {
                        let currentName = ingMap.scalarString(key: "name", txn: txn) ?? ""
                        let expectedTrimmed = expectedName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let currentTrimmed = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard expectedTrimmed == currentTrimmed else { return }
                    }
                    RecipeYjsWriter.applyIllustrationPickerBinding(
                        to: ingMap,
                        illustrationId: binding.illustrationId,
                        pickerCleared: binding.pickerCleared,
                        txn: txn
                    )
                }
            }
        }
    }

    func removeIngredient(id ingredientId: String) throws {
        try RecipeYjsWriter.withIngredientsArray(in: map, txn: txn) { array in
            let len = array.length(txn: txn)
            for index in 0..<len {
                if let id = array.withMap(at: index, txn: txn, { $0.scalarString(key: "id", txn: txn) }),
                   id == ingredientId {
                    array.remove(at: index, len: 1, txn: txn)
                    RecipeYjsWriter.renumberIngredientOrders(in: array, txn: txn)
                    break
                }
            }
        }
        // Dual-write (root + nested) — see `updateIngredient`.
        setNutritionOutdated(true)
    }

    /// Move the element at `fromIndex` to `toIndex` and renumber orders.
    /// Caller is responsible for bounds-checking relative to the current array
    /// length; the function silently no-ops when indices are out of range.
    func moveIngredient(from fromIndex: Int, to toIndex: Int) throws {
        try RecipeYjsWriter.withIngredientsArray(in: map, txn: txn) { array in
            let len = Int(array.length(txn: txn))
            guard fromIndex >= 0, toIndex >= 0, fromIndex < len, toIndex < len else { return }

            var moved: IngredientData?
            array.withMap(at: UInt32(fromIndex), txn: txn) { ingMap in
                moved = RecipeYjsCodec.parseIngredientMap(ingMap, txn: txn, fallbackOrder: fromIndex + 1)
            }
            guard let moved else { return }

            array.remove(at: UInt32(fromIndex), len: 1, txn: txn)
            let insertAt = toIndex > fromIndex ? toIndex - 1 : toIndex
            try RecipeYjsWriter.insertIngredient(moved, into: array, at: UInt32(insertAt), txn: txn)
            RecipeYjsWriter.renumberIngredientOrders(in: array, txn: txn)
        }
    }
}

/// Typed write-handle for a recipe entry inside the `recipes` Y.Array of the
/// collection document. Same lifecycle as `RecipeMapWriter`.
struct CollectionEntryWriter {
    let map: YrsMap
    let txn: OpaquePointer

    func setName(_ name: String) {
        map.insert(key: "name", value: .string(name), txn: txn)
    }

    func setImageUrl(_ imageUrl: String) {
        map.insert(key: "imageUrl", value: .string(imageUrl), txn: txn)
    }

    func clearImageUrl() {
        _ = map.remove(key: "imageUrl", txn: txn)
    }

    func setColor(_ color: String) {
        map.insert(key: "color", value: .string(color), txn: txn)
    }

    func setIsPinned(_ isPinned: Bool) {
        map.insert(key: "isPinned", value: .bool(isPinned), txn: txn)
    }

    /// Soft-delete the entry (web `tombstoneRecipeEntry`).
    func tombstone() {
        map.insert(key: "deleted", value: .bool(true), txn: txn)
    }
}

/// Typed write-handle for a folder entry inside the `folders` Y.Array of the
/// collection document. `mutateFolderEntry` bumps `updatedAt` automatically.
struct FolderEntryWriter {
    let map: YrsMap
    let txn: OpaquePointer

    func setName(_ name: String) {
        map.insert(key: "name", value: .string(name), txn: txn)
    }

    func setColor(_ color: String) {
        map.insert(key: "color", value: .string(color), txn: txn)
    }
}
