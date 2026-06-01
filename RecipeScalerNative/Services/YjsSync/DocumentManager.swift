import Foundation
import OSLog
import YrsC

/// Manages Y.Doc instances and provides parsed domain models from CRDT data.
///
/// Thread-safe via actor isolation. Each Y.Doc is identified by its document key
/// (`{userId}:collection` or `{userId}:recipe:{recipeId}`).
actor DocumentManager {
    private var docs: [String: YrsDocument] = [:]
    private let store: YDocStore
    private static let logger = Logger(subsystem: "com.recipescaler.native", category: "DocumentManager")

    init(store: YDocStore) {
        self.store = store
    }

    // ─── Document Lifecycle ──────────────────────────────────────────────

    func getOrCreateDoc(key: String) async throws -> YrsDocument {
        if let existing = docs[key] {
            return existing
        }

        let doc: YrsDocument
        if let snapshot = try? await store.loadSnapshot(docKey: key) {
            Self.logger.info("Loading doc \(key) from SQLite snapshot (\(snapshot.state.count) bytes)")
            do {
                doc = try YrsDocument(state: snapshot.state)
            } catch {
                Self.logger.warning("Corrupted snapshot for \(key), deleting and creating empty doc")
                try? await store.deleteSnapshot(docKey: key)
                doc = try YrsDocument()
            }
        } else {
            Self.logger.info("Creating empty doc for \(key)")
            doc = try YrsDocument()
        }

        docs[key] = doc
        return doc
    }

    func getDoc(key: String) -> YrsDocument? {
        return docs[key]
    }

    func applyUpdate(key: String, data: Data, lastSyncedAt: String? = nil) async throws {
        let doc = try await getOrCreateDoc(key: key)
        try await doc.applyUpdate(data)

        if let state = await doc.encodeStateAsUpdate() {
            try? await store.saveSnapshot(docKey: key, state: state, lastSyncedAt: lastSyncedAt)
        }
    }

    func evictDoc(key: String) {
        docs.removeValue(forKey: key)
        Self.logger.info("Evicted doc \(key) from memory")
    }

    func evictAll() {
        docs.removeAll()
        Self.logger.info("Evicted all docs from memory")
    }

    // ─── Collection Reading ──────────────────────────────────────────────

    func readCollectionEntries() async throws -> [CollectionEntry] {
        let doc = try await getOrCreateDoc(key: currentCollectionKey)
        let entries: [CollectionEntry] = try await doc.withReadTransaction { rawDoc, txn in
            guard let arrayBranch = yarray(rawDoc, "recipes") else {
                Self.logger.warning("No 'recipes' Y.Array found in collection doc")
                return []
            }
            let array = YrsArray(branch: arrayBranch)
            let count = array.length(txn: txn)
            Self.logger.info("Reading \(count) collection entries")

            var result: [CollectionEntry] = []
            for i in 0..<count {
                guard let map = array.getMap(index: i, txn: txn) else { continue }
                result.append(self.parseCollectionEntry(from: map, txn: txn))
            }
            return result
        }
        return entries
    }

    // ─── Recipe Reading ──────────────────────────────────────────────────

    func readRecipeData(recipeId: String, userId: String) async throws -> RecipeData? {
        let key = "\(userId):recipe:\(recipeId)"
        guard let doc = docs[key] else {
            Self.logger.info("Recipe doc \(key) not loaded")
            return nil
        }

        let result: RecipeData? = try await doc.withReadTransaction { rawDoc, txn in
            guard let mapBranch = ymap(rawDoc, "recipe") else {
                Self.logger.warning("No 'recipe' Y.Map found in recipe doc \(key)")
                return nil as RecipeData?
            }
            let map = YrsMap(branch: mapBranch)
            return self.parseRecipeData(from: map, txn: txn, recipeId: recipeId)
        }
        return result
    }

    // ─── State Persistence ───────────────────────────────────────────────

    func persistAll() async {
        for (key, doc) in self.docs {
            if let state = await doc.encodeStateAsUpdate() {
                try? await self.store.saveSnapshot(docKey: key, state: state, lastSyncedAt: nil)
            }
        }
        Self.logger.info("Persisted \(self.docs.count) documents to SQLite")
    }

    // MARK: - Private

    private var currentCollectionKey: String = ""

    func setUserId(_ userId: String) {
        self.currentCollectionKey = "\(userId):collection"
    }

    // ─── Parsing Helpers ─────────────────────────────────────────────────

    private func parseCollectionEntry(from map: YrsMap, txn: OpaquePointer) -> CollectionEntry {
        CollectionEntry(
            id: map.string(key: "id", txn: txn) ?? UUID().uuidString,
            name: map.string(key: "name", txn: txn) ?? "",
            color: map.string(key: "color", txn: txn) ?? "#3b82f6",
            imageUrl: map.string(key: "imageUrl", txn: txn),
            updatedAt: map.string(key: "updatedAt", txn: txn) ?? "",
            deleted: map.bool(key: "deleted", txn: txn) ?? false,
            isPinned: map.bool(key: "isPinned", txn: txn) ?? false
        )
    }

    private func parseRecipeData(from map: YrsMap, txn: OpaquePointer, recipeId: String) -> RecipeData {
        let versionString = map.string(key: "version", txn: txn)
        let version = RecipeData.RecipeVersion.detect(versionString)

        return RecipeData(
            id: recipeId,
            name: map.string(key: "name", txn: txn) ?? "",
            servings: map.int(key: "servings", txn: txn) ?? 1,
            color: map.string(key: "color", txn: txn) ?? "#3b82f6",
            version: versionString ?? "v1",
            description: readDescription(from: map, txn: txn, version: version),
            ingredients: readIngredients(from: map, txn: txn, version: version),
            nutrition: readNutrition(from: map, txn: txn, version: version),
            isPublic: map.bool(key: "isPublic", txn: txn) ?? false,
            hasSteps: map.bool(key: "hasSteps", txn: txn) ?? false,
            createdAt: map.string(key: "createdAt", txn: txn) ?? "",
            updatedAt: map.string(key: "updatedAt", txn: txn) ?? "",
            imageUrl: map.string(key: "imageUrl", txn: txn),
            imageAspectRatio: map.double(key: "imageAspectRatio", txn: txn),
            originalRecipeLink: map.string(key: "originalRecipeLink", txn: txn),
            originalRecipe: map.string(key: "originalRecipe", txn: txn)
        )
    }

    // ─── Version-Aware Field Readers ─────────────────────────────────────

    private func readDescription(
        from map: YrsMap,
        txn: OpaquePointer,
        version: RecipeData.RecipeVersion
    ) -> String? {
        switch version {
        case .v1:
            return map.string(key: "description", txn: txn)
        case .v2:
            guard let textBranch = map.nestedText(key: "description", txn: txn) else {
                return map.string(key: "description", txn: txn)
            }
            return YrsText(branch: textBranch).string(txn: txn)
        case .v3:
            return nil
        }
    }

    private func readIngredients(
        from map: YrsMap,
        txn: OpaquePointer,
        version: RecipeData.RecipeVersion
    ) -> [IngredientData] {
        switch version {
        case .v1:
            guard let json = map.string(key: "ingredients", txn: txn) else { return [] }
            return parseJSONIngredients(json)
        case .v2, .v3:
            guard let arrayBranch = map.nestedArray(key: "ingredients", txn: txn) else { return [] }
            let array = YrsArray(branch: arrayBranch)
            return array.iterateMaps(txn: txn).enumerated().map { index, ingMap in
                IngredientData(
                    id: ingMap.string(key: "id", txn: txn) ?? UUID().uuidString,
                    name: ingMap.string(key: "name", txn: txn) ?? "",
                    amount: ingMap.string(key: "amount", txn: txn) ?? "",
                    originalAmount: ingMap.string(key: "originalAmount", txn: txn) ?? "",
                    order: ingMap.int(key: "order", txn: txn) ?? (index + 1)
                )
            }
        }
    }

    private func readNutrition(
        from map: YrsMap,
        txn: OpaquePointer,
        version: RecipeData.RecipeVersion
    ) -> NutritionData? {
        let val = map.value(key: "nutrition", txn: txn)

        if val.tag == YrsValue.Y_MAP {
            guard let mapBranch = val.mapBranch else { return nil }
            let nMap = YrsMap(branch: mapBranch)
            return NutritionData(
                calories: nMap.double(key: "calories", txn: txn),
                protein: nMap.double(key: "protein", txn: txn),
                fat: nMap.double(key: "fat", txn: txn),
                carbs: nMap.double(key: "carbs", txn: txn),
                extra: [:]
            )
        } else if val.tag == YrsValue.Y_JSON_STR {
            guard let json = val.stringValue else { return nil }
            return parseJSONNutrition(json)
        }
        return nil
    }

    // ─── JSON Fallback Parsers (v1) ──────────────────────────────────────

    private func parseJSONIngredients(_ json: String) -> [IngredientData] {
        guard let data = json.data(using: .utf8) else { return [] }
        struct RawIngredient: Decodable {
            let id: String?
            let name: String?
            let amount: String?
            let originalAmount: String?
            let order: Int?
        }
        guard let raw = try? JSONDecoder().decode([RawIngredient].self, from: data) else {
            return []
        }
        return raw.enumerated().map { index, ing in
            IngredientData(
                id: ing.id ?? UUID().uuidString,
                name: ing.name ?? "",
                amount: ing.amount ?? "",
                originalAmount: ing.originalAmount ?? ing.amount ?? "",
                order: ing.order ?? (index + 1)
            )
        }
    }

    private func parseJSONNutrition(_ json: String) -> NutritionData? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return NutritionData(
            calories: dict["calories"] as? Double,
            protein: dict["protein"] as? Double,
            fat: dict["fat"] as? Double,
            carbs: dict["carbs"] as? Double,
            extra: dict.compactMapValues { $0 as? Double }
                .filter { !["calories", "protein", "fat", "carbs"].contains($0.key) }
        )
    }
}
