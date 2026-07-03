//
//  RecipeYjsCodec.swift
//  RecipeScalerNative
//

import Foundation

/// Stateless codec for decoding Yjs-loaded recipe documents into domain models.
///
/// All functions are pure: they take a `YrsMap` / `YrsArray` plus the live
/// transaction pointer and return value types. None of them touch actor state,
/// caches, or persistence — that's why they live outside `DocumentManager`.
enum RecipeYjsCodec {

    // MARK: - Collection entry

    static func parseCollectionEntry(from map: YrsMap, txn: OpaquePointer) -> CollectionEntry {
        let id = map.scalarString(key: "id", txn: txn) ?? UUID().uuidString
        let deleted = map.bool(key: "deleted", txn: txn) ?? false
        // `folderIds` is a plain JSON-array primitive on the map (not a Y.Array).
        // Missing key / non-array value → empty array (web `getRecipeFolderIds`).
        let folderIds = map.stringArray(key: RecipeFolderConstants.folderIdsKey, txn: txn)

        return CollectionEntry(
            id: id,
            name: map.scalarString(key: "name", txn: txn) ?? "",
            color: map.scalarString(key: "color", txn: txn) ?? "#3b82f6",
            imageUrl: map.scalarString(key: "imageUrl", txn: txn),
            updatedAt: map.scalarString(key: "updatedAt", txn: txn) ?? "",
            deleted: deleted,
            isPinned: map.bool(key: "isPinned", txn: txn) ?? false,
            folderIds: folderIds
        )
    }

    // MARK: - Recipe

    static func parseRecipeData(
        from map: YrsMap,
        txn: OpaquePointer,
        recipeId: String
    ) -> RecipeData {
        let versionString = map.scalarString(key: "version", txn: txn)
        let version = RecipeData.RecipeVersion.detect(versionString)
        let ingredients = readIngredients(from: map, txn: txn, version: version)

        return RecipeData(
            id: recipeId,
            name: readRecipeName(from: map, txn: txn),
            servings: RecipeServings.baseServings(from: map, txn: txn),
            color: map.scalarString(key: "color", txn: txn) ?? "#3b82f6",
            version: versionString ?? "v1",
            description: readDescription(from: map, txn: txn, version: version),
            ingredients: ingredients,
            nutrition: readNutrition(from: map, txn: txn, version: version),
            isPublic: map.bool(key: "isPublic", txn: txn) ?? false,
            hasSteps: map.bool(key: "hasSteps", txn: txn) ?? false,
            createdAt: map.scalarString(key: "createdAt", txn: txn) ?? "",
            updatedAt: map.scalarString(key: "updatedAt", txn: txn) ?? "",
            imageUrl: map.scalarString(key: "imageUrl", txn: txn),
            imageAspectRatio: map.double(key: "imageAspectRatio", txn: txn),
            originalRecipeLink: map.scalarString(key: "originalRecipeLink", txn: txn),
            originalRecipe: map.scalarString(key: "originalRecipe", txn: txn)
        )
    }

    // MARK: - Version-aware field readers

    static func readRecipeName(from map: YrsMap, txn: OpaquePointer) -> String {
        if let name = map.string(key: "name", txn: txn), !name.isEmpty {
            return name
        }
        if let nestedName = map.withNestedText(key: "name", txn: txn, { $0.string(txn: txn) }),
           let text = nestedName,
           !text.isEmpty {
            return text
        }
        return ""
    }

    static func readDescription(
        from map: YrsMap,
        txn: OpaquePointer,
        version: RecipeData.RecipeVersion
    ) -> String? {
        switch version {
        case .v1:
            return map.string(key: "description", txn: txn)
        case .v2:
            if let text = map.withNestedText(key: "description", txn: txn, { $0.string(txn: txn) }) {
                return text
            }
            return map.string(key: "description", txn: txn)
        case .v3:
            // Filled from XmlFragment after the read transaction (see DocumentManager.readRecipeData).
            if let text = map.withNestedText(key: "description", txn: txn, { $0.string(txn: txn) }) {
                return text
            }
            return map.string(key: "description", txn: txn)
        }
    }

    static func readIngredients(
        from map: YrsMap,
        txn: OpaquePointer,
        version: RecipeData.RecipeVersion,
        preferArray: Bool = false
    ) -> [IngredientData] {
        // Discover snapshots often omit the `version` field. Prefer the Y.Array
        // unconditionally when present, fall back to JSON for v1.
        if preferArray,
           let fromArray = try? map.withNestedArray(key: "ingredients", txn: txn, { array in
               var ingredients: [IngredientData] = []
               var index = 0
               array.forEachMap(txn: txn) { ingMap in
                   ingredients.append(parseIngredientMap(ingMap, txn: txn, fallbackOrder: index + 1))
                   index += 1
               }
               return ingredients
           }),
           !fromArray.isEmpty {
            return fromArray
        }

        switch version {
        case .v1:
            guard let json = map.string(key: "ingredients", txn: txn) else { return [] }
            return parseJSONIngredients(json)
        case .v2, .v3:
            return (try? map.withNestedArray(key: "ingredients", txn: txn) { array in
                var ingredients: [IngredientData] = []
                var index = 0
                array.forEachMap(txn: txn) { ingMap in
                    ingredients.append(parseIngredientMap(ingMap, txn: txn, fallbackOrder: index + 1))
                    index += 1
                }
                return ingredients
            }) ?? []
        }
    }

    static func readNutrition(
        from map: YrsMap,
        txn: OpaquePointer,
        version: RecipeData.RecipeVersion
    ) -> NutritionData? {
        // Root-level flag set by server edit API (recipe-edit-service.ts).
        let rootOutdated = map.bool(key: "nutritionOutdated", txn: txn) ?? false

        if let parsed = try? map.withNestedMap(key: "nutrition", txn: txn, { nMap in
            var extra: [String: Double] = [:]
            if let totalWeight = nMap.double(key: "totalWeight", txn: txn) {
                extra["totalWeight"] = totalWeight
            }
            let nutritionOutdated = nMap.bool(key: "nutritionOutdated", txn: txn) ?? false
            return NutritionData(
                calories: nMap.double(key: "calories", txn: txn),
                protein: nMap.double(key: "protein", txn: txn),
                fat: nMap.double(key: "fat", txn: txn),
                carbs: nMap.double(key: "carbs", txn: txn),
                nutritionOutdated: rootOutdated || nutritionOutdated,
                extra: extra
            )
        }) {
            return parsed
        }

        guard let val = map.value(key: "nutrition", txn: txn),
              val.tag == YrsValue.Y_JSON_STR,
              let json = val.stringValue else {
            return nil
        }
        var result = parseJSONNutrition(json)
        if rootOutdated, var modifiable = result {
            result = NutritionData(
                calories: modifiable.calories,
                protein: modifiable.protein,
                fat: modifiable.fat,
                carbs: modifiable.carbs,
                nutritionOutdated: true,
                extra: modifiable.extra
            )
        }
        return result
    }

    // MARK: - Search projection

    struct SearchIngredientProjection {
        let names: [String]
        let amounts: [String]
    }

    static func readSearchIngredients(
        from map: YrsMap,
        txn: OpaquePointer,
        version: RecipeData.RecipeVersion
    ) -> SearchIngredientProjection {
        switch version {
        case .v1:
            guard let json = map.string(key: "ingredients", txn: txn) else {
                return SearchIngredientProjection(names: [], amounts: [])
            }
            return searchIngredientsFromJSON(json)
        case .v2, .v3:
            let projection = (try? map.withNestedArray(key: "ingredients", txn: txn) { array in
                var names: [String] = []
                var amounts: [String] = []
                array.forEachMap(txn: txn) { ingMap in
                    let isSeparator = ingMap.bool(key: "isSeparator", txn: txn) ?? false
                    guard !isSeparator else { return }
                    let name = ingMap.scalarString(key: "name", txn: txn) ?? ""
                    guard !name.isEmpty else { return }
                    names.append(name)
                    let originalAmount = ingMap.scalarString(key: "originalAmount", txn: txn) ?? ""
                    let amount = ingMap.scalarString(key: "amount", txn: txn) ?? ""
                    amounts.append(!originalAmount.isEmpty ? originalAmount : amount)
                }
                return SearchIngredientProjection(names: names, amounts: amounts)
            })
            return projection ?? SearchIngredientProjection(names: [], amounts: [])
        }
    }

    static func searchIngredientsFromJSON(_ json: String) -> SearchIngredientProjection {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return SearchIngredientProjection(names: [], amounts: [])
        }
        var names: [String] = []
        var amounts: [String] = []
        for dict in raw {
            let isSeparator = dict["isSeparator"] as? Bool ?? false
            guard !isSeparator else { continue }
            let name = dict["name"] as? String ?? ""
            guard !name.isEmpty else { continue }
            names.append(name)
            let originalAmount: String = {
                if dict["originalAmount"] is NSNull { return "" }
                if let number = dict["originalAmount"] as? NSNumber {
                    return IngredientData.formatScalarNumber(number.doubleValue)
                }
                if let string = dict["originalAmount"] as? String { return string }
                return ""
            }()
            let amount: String = {
                if let number = dict["amount"] as? NSNumber {
                    return IngredientData.formatScalarNumber(number.doubleValue)
                }
                if let string = dict["amount"] as? String { return string }
                return ""
            }()
            amounts.append(!originalAmount.isEmpty ? originalAmount : amount)
        }
        return SearchIngredientProjection(names: names, amounts: amounts)
    }

    // MARK: - Folder

    /// Parse a folder Y.Map into `RecipeFolder`. Returns nil when the entry
    /// is missing an `id` or the id is empty (matches web `folderEntryToObject`).
    static func parseRecipeFolder(from map: YrsMap, txn: OpaquePointer) -> RecipeFolder? {
        guard let id = map.scalarString(key: "id", txn: txn), !id.isEmpty else {
            return nil
        }
        let updatedAt = map.scalarString(key: "updatedAt", txn: txn) ?? ISO8601DateFormatter().string(from: Date())
        let rawName = map.scalarString(key: "name", txn: txn) ?? ""
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedName = trimmedName.isEmpty
            ? RecipeFolderConstants.untitledFolderNameSentinel
            : trimmedName
        let color = map.scalarString(key: "color", txn: txn) ?? RecipeFolderConstants.defaultFolderColor
        let createdAt = map.scalarString(key: "createdAt", txn: txn) ?? updatedAt
        let deleted = map.bool(key: "deleted", txn: txn) ?? false
        return RecipeFolder(
            id: id,
            name: storedName,
            color: color,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deleted: deleted
        )
    }

    // MARK: - JSON Fallback Parsers (v1)

    static func parseIngredientMap(
        _ ingMap: YrsMap,
        txn: OpaquePointer,
        fallbackOrder: Int
    ) -> IngredientData {
        let unit = ingMap.scalarString(key: "unit", txn: txn) ?? ""
        let amount = ingMap.scalarString(key: "amount", txn: txn) ?? ""
        let originalAmount = ingMap.scalarString(key: "originalAmount", txn: txn) ?? ""
        let isSeparator = ingMap.bool(key: "isSeparator", txn: txn) ?? false
        // Web parity: an ingredient "has quantity" when either amount is filled.
        let hasQuantity = !originalAmount.isEmpty || !amount.isEmpty

        let illustrationId = ingMap.scalarString(key: "illustrationId", txn: txn)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIllustrationId = illustrationId?.isEmpty == false ? illustrationId : nil

        return IngredientData(
            id: ingMap.scalarString(key: "id", txn: txn) ?? UUID().uuidString,
            name: ingMap.scalarString(key: "name", txn: txn) ?? "",
            amount: amount,
            originalAmount: originalAmount,
            unit: unit,
            order: ingMap.int(key: "order", txn: txn) ?? fallbackOrder,
            isSeparator: isSeparator,
            hasQuantity: hasQuantity,
            calories: ingMap.double(key: "calories", txn: txn),
            protein: ingMap.double(key: "protein", txn: txn),
            fat: ingMap.double(key: "fat", txn: txn),
            carbs: ingMap.double(key: "carbs", txn: txn),
            weight: ingMap.double(key: "weight", txn: txn),
            illustrationId: resolvedIllustrationId,
            illustrationPickerCleared: ingMap.bool(key: "illustrationPickerCleared", txn: txn) ?? false
        )
    }

    static func parseJSONIngredients(_ json: String) -> [IngredientData] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return raw.enumerated().map { index, dict in
            let id = dict["id"] as? String ?? UUID().uuidString
            let name = dict["name"] as? String ?? ""
            let unit = dict["unit"] as? String ?? ""
            let isSeparator = dict["isSeparator"] as? Bool ?? false
            let order = dict["order"] as? Int ?? (index + 1)

            let originalAmount: String = {
                if dict["originalAmount"] is NSNull { return "" }
                if let number = dict["originalAmount"] as? NSNumber {
                    return IngredientData.formatScalarNumber(number.doubleValue)
                }
                if let string = dict["originalAmount"] as? String { return string }
                return ""
            }()

            let amount: String = {
                if let number = dict["amount"] as? NSNumber {
                    return IngredientData.formatScalarNumber(number.doubleValue)
                }
                if let string = dict["amount"] as? String { return string }
                return ""
            }()

            let hasQuantity = !originalAmount.isEmpty || !amount.isEmpty

            let rawIllustrationId = dict["illustrationId"] as? String
            let illustrationId = rawIllustrationId?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedIllustrationId = illustrationId?.isEmpty == false ? illustrationId : nil

            return IngredientData(
                id: id,
                name: name,
                amount: amount,
                originalAmount: originalAmount.isEmpty ? amount : originalAmount,
                unit: unit,
                order: order,
                isSeparator: isSeparator,
                hasQuantity: hasQuantity,
                calories: dict["calories"] as? Double ?? (dict["calories"] as? NSNumber)?.doubleValue,
                protein: dict["protein"] as? Double ?? (dict["protein"] as? NSNumber)?.doubleValue,
                fat: dict["fat"] as? Double ?? (dict["fat"] as? NSNumber)?.doubleValue,
                carbs: dict["carbs"] as? Double ?? (dict["carbs"] as? NSNumber)?.doubleValue,
                weight: dict["weight"] as? Double ?? (dict["weight"] as? NSNumber)?.doubleValue,
                illustrationId: resolvedIllustrationId,
                illustrationPickerCleared: dict["illustrationPickerCleared"] as? Bool ?? false
            )
        }
    }

    static func parseJSONNutrition(_ json: String) -> NutritionData? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let nutritionOutdated = dict["nutritionOutdated"] as? Bool ?? false
        return NutritionData(
            calories: dict["calories"] as? Double,
            protein: dict["protein"] as? Double,
            fat: dict["fat"] as? Double,
            carbs: dict["carbs"] as? Double,
            nutritionOutdated: nutritionOutdated,
            extra: dict.compactMapValues { $0 as? Double }
                .filter { !["calories", "protein", "fat", "carbs"].contains($0.key) }
        )
    }
}
