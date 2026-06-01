import Foundation
import OSLog
import YrsC

/// Manages Y.Doc instances and provides parsed domain models from CRDT data.
///
/// Thread-safe via actor isolation. Each Y.Doc is identified by its document key
/// (`{userId}:collection` or `{userId}:recipe:{recipeId}`).
actor DocumentManager {
    private var docs: [String: YrsDocument] = [:]
    private var observerTokens: [String: YrsObserverToken] = [:]
    private let store: YDocStore
    private static let logger = Logger(subsystem: "com.recipescaler.native", category: "DocumentManager")

    private var onCollectionChanged: (@Sendable () -> Void)?
    private var onRecipeChanged: (@Sendable (String) -> Void)?

    init(store: YDocStore) {
        self.store = store
    }

    func setChangeHandlers(
        onCollectionChanged: @escaping @Sendable () -> Void,
        onRecipeChanged: @escaping @Sendable (String) -> Void
    ) {
        self.onCollectionChanged = onCollectionChanged
        self.onRecipeChanged = onRecipeChanged
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
        await installObservers(key: key, doc: doc)
        return doc
    }

    func getDoc(key: String) -> YrsDocument? {
        return docs[key]
    }

    func applyUpdate(key: String, data: Data, lastSyncedAt: String? = nil) async throws {
        let doc = try await getOrCreateDoc(key: key)
        do {
            try await doc.applyUpdate(data)
        } catch {
            Self.logger.warning("applyUpdate failed for \(key), deleting corrupted snapshot")
            docs.removeValue(forKey: key)
            observerTokens.removeValue(forKey: key)
            try? await store.deleteSnapshot(docKey: key)
            throw error
        }

        if let state = await doc.encodeStateAsUpdate() {
            try? await store.saveSnapshot(docKey: key, state: state, lastSyncedAt: lastSyncedAt)
        }
    }

    /// Replace an in-memory document with a full server snapshot (used on `document_loaded`).
    func replaceDocument(key: String, state: Data, lastSyncedAt: String? = nil) async throws {
        docs.removeValue(forKey: key)
        observerTokens.removeValue(forKey: key)
        let doc = try YrsDocument(state: state)
        docs[key] = doc
        try? await store.saveSnapshot(docKey: key, state: state, lastSyncedAt: lastSyncedAt)
        await installObservers(key: key, doc: doc)
        Self.logger.info("Replaced doc \(key) from server snapshot (\(state.count) bytes)")
    }

    func evictDoc(key: String) {
        docs.removeValue(forKey: key)
        observerTokens.removeValue(forKey: key)
        Self.logger.info("Evicted doc \(key) from memory")
    }

    func evictAll() {
        docs.removeAll()
        Self.logger.info("Evicted all docs from memory")
    }

    // ─── Collection Reading ──────────────────────────────────────────────

    func readCollectionEntries() async throws -> [CollectionEntry] {
        let doc = try await getOrCreateDoc(key: currentCollectionKey)
        let entries: [CollectionEntry] = try await doc.withReadTransaction { _, txn in
            guard let arrayBranch = ytype_get(txn, "recipes") else {
                Self.logger.warning("No 'recipes' Y.Array found in collection doc")
                return []
            }
            let array = YrsArray(branch: arrayBranch)
            var result: [CollectionEntry] = []
            try array.forEachMap(txn: txn) { map in
                result.append(self.parseCollectionEntry(from: map, txn: txn))
            }
            if result.isEmpty {
                Self.logger.warning("Parsed 0 collection entries (recipes array length=\(array.length(txn: txn)))")
            } else {
                Self.logger.info("Parsed \(result.count) collection entries")
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
            guard let mapBranch = ytype_get(txn, "recipe") else {
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

    private func installObservers(key: String, doc: YrsDocument) async {
        observerTokens.removeValue(forKey: key)

        if key.hasSuffix(":collection"), let handler = onCollectionChanged {
            if let token = try? await doc.addDeepObserver(rootKey: "recipes", handler: handler) {
                observerTokens[key] = token
            }
            return
        }

        guard let recipeId = recipeId(fromDocKey: key),
              let handler = onRecipeChanged else { return }
        let recipeHandler: @Sendable () -> Void = { handler(recipeId) }
        if let token = try? await doc.addDeepObserver(rootKey: "recipe", handler: recipeHandler) {
            observerTokens[key] = token
        }
    }

    private func recipeId(fromDocKey key: String) -> String? {
        guard let range = key.range(of: ":recipe:") else { return nil }
        let id = String(key[range.upperBound...])
        return id.isEmpty ? nil : id
    }

    // ─── Parsing Helpers ─────────────────────────────────────────────────

    private func parseCollectionEntry(from map: YrsMap, txn: OpaquePointer) -> CollectionEntry {
        let id = map.string(key: "id", txn: txn) ?? UUID().uuidString
        let deleted = map.bool(key: "deleted", txn: txn) ?? false

        return CollectionEntry(
            id: id,
            name: map.string(key: "name", txn: txn) ?? "",
            color: map.string(key: "color", txn: txn) ?? "#3b82f6",
            imageUrl: map.string(key: "imageUrl", txn: txn),
            updatedAt: map.string(key: "updatedAt", txn: txn) ?? "",
            deleted: deleted,
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
            if let text = map.withNestedText(key: "description", txn: txn, { $0.string(txn: txn) }) {
                return text
            }
            return map.string(key: "description", txn: txn)
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
            return (try? map.withNestedArray(key: "ingredients", txn: txn) { array in
                var ingredients: [IngredientData] = []
                var index = 0
                array.forEachMap(txn: txn) { ingMap in
                    ingredients.append(
                        IngredientData(
                            id: ingMap.string(key: "id", txn: txn) ?? UUID().uuidString,
                            name: ingMap.string(key: "name", txn: txn) ?? "",
                            amount: ingMap.string(key: "amount", txn: txn) ?? "",
                            originalAmount: ingMap.string(key: "originalAmount", txn: txn) ?? "",
                            order: ingMap.int(key: "order", txn: txn) ?? (index + 1)
                        )
                    )
                    index += 1
                }
                return ingredients
            }) ?? []
        }
    }

    private func readNutrition(
        from map: YrsMap,
        txn: OpaquePointer,
        version: RecipeData.RecipeVersion
    ) -> NutritionData? {
        guard let val = map.value(key: "nutrition", txn: txn) else { return nil }

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
