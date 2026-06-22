//
//  RecipeReader.swift
//  RecipeScalerNative
//

import Foundation

/// One-shot parser that turns a Yjs v1 state update (binary `Data`) into a
/// minimal `RecipeData` for read-only display in Discover. Avoids activating
/// the full `DocumentManager` editing session — we just want to render.
///
/// Field decoding delegates to `RecipeYjsCodec` (shared with the editing
/// pipeline) so behavior stays in lockstep between Discover and the editor.
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

    /// Discover projection: only the fields needed for read-only rendering.
    /// Uses `RecipeYjsCodec` for parity with the editing pipeline but keeps
    /// its own `RecipeFields` bucket (servings, image, original-link — fields
    /// `RecipeYjsCodec.parseRecipeData` doesn't surface in the same shape).
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
            name: RecipeYjsCodec.readRecipeName(from: map, txn: txn),
            color: map.scalarString(key: "color", txn: txn) ?? "#3b82f6",
            servings: RecipeServings.baseServings(from: map, txn: txn),
            version: versionString,
            description: RecipeYjsCodec.readDescription(from: map, txn: txn, version: version),
            // Public snapshots often omit `version`; prefer the Y.Array when present.
            ingredients: RecipeYjsCodec.readIngredients(
                from: map,
                txn: txn,
                version: version,
                preferArray: true
            ),
            nutrition: RecipeYjsCodec.readNutrition(from: map, txn: txn, version: version),
            imageUrl: map.scalarString(key: "imageUrl", txn: txn),
            imageAspectRatio: map.double(key: "imageAspectRatio", txn: txn),
            originalRecipeLink: map.scalarString(key: "originalRecipeLink", txn: txn)
        )
    }
}
