//
//  RecipeReader.swift
//  RecipeScalerNative
//

import Foundation

/// One-shot parser that turns a Yjs v1 state update (binary `Data`) into a
/// minimal `RecipeData` for read-only display in Discover. Avoids activating
/// the full `DocumentManager` editing session — we just want to render.
///
/// Reuses the same Yrs FFI patterns as `DocumentManager.parseRecipeData` but
/// only reads fields needed for display: name, color, servings, ingredients,
/// description. Nutrition / version flags are not surfaced here.
enum RecipeReader {
    /// Apply `state` to a fresh `Y.Doc` and read the `recipe` root map.
    /// Returns `nil` if the bytes are malformed or there is no `recipe` map.
    static func parse(state: Data, recipeId: String) async -> RecipeData? {
        guard let doc = try? YrsDocument(state: state) else { return nil }

        var xmlSnapshot: String?
        var recipeFields: RecipeFields?

        do {
            try await doc.withReadTransaction { _, txn in
                guard let map = doc.recipeMap(txn: txn) else { return }
                recipeFields = readFields(from: map, txn: txn)

                // v3 description lives in XmlFragment — capture whenever it has content
                // (public recipes may omit the `version` field).
                if let fragment = doc.xmlFragment(txn: txn, name: "description") {
                    xmlSnapshot = XmlFragmentToHTML.serializedFragment(from: fragment, txn: txn)
                }
            }
        } catch {
            return nil
        }

        guard let fields = recipeFields else { return nil }

        // Convert v3 XML → HTML after the txn closes (post-processing).
        var description = fields.description
        if let xml = xmlSnapshot,
           let html = XmlFragmentToHTML.html(
               fromSerializedXML: xml,
               ingredients: fields.ingredients
           ),
           !html.isEmpty {
            description = html
        }

        return RecipeData(
            id: recipeId,
            name: fields.name,
            servings: fields.servings,
            color: fields.color,
            version: fields.version ?? "v1",
            description: description,
            ingredients: fields.ingredients,
            nutrition: fields.nutrition,
            isPublic: false,
            hasSteps: false,
            createdAt: "",
            updatedAt: "",
            imageUrl: fields.imageUrl,
            imageAspectRatio: fields.imageAspectRatio,
            originalRecipeLink: fields.originalRecipeLink,
            originalRecipe: nil
        )
    }

    private struct RecipeFields {
        var name: String
        var color: String
        var servings: Int
        var version: String?
        var description: String?
        var ingredients: [IngredientData]
        var nutrition: NutritionData?
        var imageUrl: String?
        var imageAspectRatio: Double?
        var originalRecipeLink: String?
    }

    private static func readFields(
        from map: YrsMap,
        txn: OpaquePointer
    ) -> RecipeFields {
        let versionString = map.scalarString(key: "version", txn: txn)
        let version = RecipeData.RecipeVersion.detect(versionString)

        return RecipeFields(
            name: readName(from: map, txn: txn),
            color: map.scalarString(key: "color", txn: txn) ?? "#3b82f6",
            servings: RecipeServings.baseServings(from: map, txn: txn),
            version: versionString,
            description: readDescription(from: map, txn: txn, version: version),
            ingredients: readIngredients(from: map, txn: txn, version: version),
            nutrition: readNutrition(from: map, txn: txn),
            imageUrl: map.scalarString(key: "imageUrl", txn: txn),
            imageAspectRatio: map.double(key: "imageAspectRatio", txn: txn),
            originalRecipeLink: map.scalarString(key: "originalRecipeLink", txn: txn)
        )
    }

    private static func readName(from map: YrsMap, txn: OpaquePointer) -> String {
        if let name = map.string(key: "name", txn: txn), !name.isEmpty {
            return name
        }
        if let optionalText = map.withNestedText(key: "name", txn: txn, { $0.string(txn: txn) }),
           let text = optionalText,
           !text.isEmpty {
            return text
        }
        return ""
    }

    private static func readDescription(
        from map: YrsMap,
        txn: OpaquePointer,
        version: RecipeData.RecipeVersion
    ) -> String? {
        if let text = map.withNestedText(key: "description", txn: txn, { $0.string(txn: txn) }) {
            return text
        }
        return map.string(key: "description", txn: txn)
    }

    private static func readNutrition(from map: YrsMap, txn: OpaquePointer) -> NutritionData? {
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
              let json = val.stringValue,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let nutritionOutdated = dict["nutritionOutdated"] as? Bool ?? false
        return NutritionData(
            calories: dict["calories"] as? Double,
            protein: dict["protein"] as? Double,
            fat: dict["fat"] as? Double,
            carbs: dict["carbs"] as? Double,
            nutritionOutdated: rootOutdated || nutritionOutdated,
            extra: dict.compactMapValues { $0 as? Double }
                .filter { !["calories", "protein", "fat", "carbs", "nutritionOutdated"].contains($0.key) }
        )
    }

    private static func readIngredients(
        from map: YrsMap,
        txn: OpaquePointer,
        version: RecipeData.RecipeVersion
    ) -> [IngredientData] {
        // Prefer Y.Array (v2/v3) regardless of `version` — public snapshots often omit it.
        if let fromArray = try? map.withNestedArray(key: "ingredients", txn: txn, { array in
            var ingredients: [IngredientData] = []
            var index = 0
            array.forEachMap(txn: txn) { ingMap in
                ingredients.append(parseIngredient(ingMap, txn: txn, order: index + 1))
                index += 1
            }
            return ingredients
        }), !fromArray.isEmpty {
            return fromArray
        }

        switch version {
        case .v1:
            guard let json = map.string(key: "ingredients", txn: txn) else { return [] }
            return parseJSONIngredients(json)
        case .v2, .v3:
            return []
        }
    }

    private static func parseIngredient(
        _ map: YrsMap,
        txn: OpaquePointer,
        order: Int
    ) -> IngredientData {
        let isSeparator = map.bool(key: "isSeparator", txn: txn) ?? false
        let amountDouble = map.double(key: "amount", txn: txn)
        let hasOriginal = !map.isNullOrMissing(key: "originalAmount", txn: txn)
        let originalAmountDouble = map.double(key: "originalAmount", txn: txn)
        let amountString = map.scalarString(key: "amount", txn: txn)
            ?? amountDouble.map(formatAmount)
            ?? ""
        let originalAmountString = map.scalarString(key: "originalAmount", txn: txn)
            ?? originalAmountDouble.map(formatAmount)
            ?? ""
        let hasQuantity = hasOriginal && !originalAmountString.isEmpty
        return IngredientData(
            id: map.scalarString(key: "id", txn: txn) ?? UUID().uuidString,
            name: map.scalarString(key: "name", txn: txn) ?? "",
            amount: amountString,
            originalAmount: originalAmountString,
            unit: map.scalarString(key: "unit", txn: txn) ?? "",
            order: map.int(key: "order", txn: txn) ?? order,
            isSeparator: isSeparator,
            hasQuantity: hasQuantity,
            calories: map.double(key: "calories", txn: txn),
            protein: map.double(key: "protein", txn: txn),
            fat: map.double(key: "fat", txn: txn),
            carbs: map.double(key: "carbs", txn: txn),
            weight: map.double(key: "weight", txn: txn)
        )
    }

    private static func parseJSONIngredients(_ json: String) -> [IngredientData] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.enumerated().map { idx, dict in
            let amountDouble = (dict["amount"] as? Double) ?? ((dict["amount"] as? String)).flatMap(Double.init)
            let originalAmountDouble = (dict["originalAmount"] as? Double) ?? ((dict["originalAmount"] as? String)).flatMap(Double.init)
            return IngredientData(
                id: (dict["id"] as? String) ?? UUID().uuidString,
                name: (dict["name"] as? String) ?? "",
                amount: (dict["amount"] as? String) ?? amountDouble.map(formatAmount) ?? "",
                originalAmount: (dict["originalAmount"] as? String) ?? originalAmountDouble.map(formatAmount) ?? "",
                unit: (dict["unit"] as? String) ?? "",
                order: (dict["order"] as? Int) ?? (idx + 1),
                isSeparator: (dict["isSeparator"] as? Bool) ?? false,
                hasQuantity: originalAmountDouble != nil,
                calories: (dict["calories"] as? Double),
                protein: (dict["protein"] as? Double),
                fat: (dict["fat"] as? Double),
                carbs: (dict["carbs"] as? Double),
                weight: (dict["weight"] as? Double)
            )
        }
    }

    private static func formatAmount(_ value: Double) -> String {
        // Trim trailing zeros (1.0 → "1", 1.5 → "1.5") for display parity.
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
