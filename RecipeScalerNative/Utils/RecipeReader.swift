//
//  RecipeReader.swift
//  RecipeScalerNative
//

import Foundation
import YrsC

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
                guard let mapBranch = ytype_get(txn, "recipe") else { return }
                let map = YrsMap(branch: mapBranch)
                recipeFields = readFields(from: map, txn: txn)

                // Capture the v3 description XML inside the txn (FFI walk requires active txn).
                if let version = recipeFields?.version,
                   RecipeData.RecipeVersion.detect(version) == .v3 {
                    xmlSnapshot = XmlFragmentToHTML.serializedFragment(txn: txn)
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
            nutrition: nil,
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

    private static func readIngredients(
        from map: YrsMap,
        txn: OpaquePointer,
        version: RecipeData.RecipeVersion
    ) -> [IngredientData] {
        switch version {
        case .v1:
            guard let json = map.string(key: "ingredients", txn: txn) else { return [] }
            return parseJSONIngredients(json)
        case .v2, .v3:
            return (try? map.withNestedArray(key: "ingredients", txn: txn) { array in
                var ingredients: [IngredientData] = []
                var index = 0
                array.forEachMap(txn: txn) { ingMap in
                    ingredients.append(parseIngredient(ingMap, txn: txn, order: index + 1))
                    index += 1
                }
                return ingredients
            }) ?? []
        }
    }

    private static func parseIngredient(
        _ map: YrsMap,
        txn: OpaquePointer,
        order: Int
    ) -> IngredientData {
        let isSeparator = map.bool(key: "isSeparator", txn: txn) ?? false
        let amountDouble = map.double(key: "amount", txn: txn)
        let originalAmountDouble = map.double(key: "originalAmount", txn: txn)
        let amountString = map.scalarString(key: "amount", txn: txn)
            ?? amountDouble.map(formatAmount)
            ?? ""
        let originalAmountString = map.scalarString(key: "originalAmount", txn: txn)
            ?? originalAmountDouble.map(formatAmount)
            ?? ""
        return IngredientData(
            id: map.scalarString(key: "id", txn: txn) ?? UUID().uuidString,
            name: map.scalarString(key: "name", txn: txn) ?? "",
            amount: amountString,
            originalAmount: originalAmountString,
            unit: map.scalarString(key: "unit", txn: txn) ?? "",
            order: map.int(key: "order", txn: txn) ?? order,
            isSeparator: isSeparator,
            hasQuantity: originalAmountDouble != nil,
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
