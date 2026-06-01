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
    private var onLocalRecipeUpdate: (@Sendable (String, Data) async -> Void)?
    private var currentUserId: String?
    private var suppressRecipeObserverDepth = 0

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

    func setLocalUpdateHandler(_ handler: @escaping @Sendable (String, Data) async -> Void) {
        onLocalRecipeUpdate = handler
    }

    // ─── Document Lifecycle ──────────────────────────────────────────────

    func getOrCreateDoc(key: String) async throws -> YrsDocument {
        if let existing = docs[key] {
            await installLocalUpdateBridge(key: key, doc: existing)
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
        await installLocalUpdateBridge(key: key, doc: doc)
        await installObservers(key: key, doc: doc)
        return doc
    }

    func getDoc(key: String) -> YrsDocument? {
        return docs[key]
    }

    func applyUpdate(key: String, data: Data, lastSyncedAt: String? = nil, suppressRecipeChangeNotification: Bool = false) async throws {
        let doc = try await getOrCreateDoc(key: key)
        if suppressRecipeChangeNotification, key.contains(":recipe:") {
            suppressRecipeObserverDepth += 1
            defer { suppressRecipeObserverDepth -= 1 }
            try await applyUpdateToDoc(doc: doc, key: key, data: data, lastSyncedAt: lastSyncedAt)
            return
        }
        try await applyUpdateToDoc(doc: doc, key: key, data: data, lastSyncedAt: lastSyncedAt)
    }

    private func applyUpdateToDoc(
        doc: YrsDocument,
        key: String,
        data: Data,
        lastSyncedAt: String?
    ) async throws {
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
        await installLocalUpdateBridge(key: key, doc: doc)
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
        self.currentUserId = userId
        self.currentCollectionKey = "\(userId):collection"
    }

    func clearOfflineQueueForAccountSwitch() async {
        try? await store.deleteAllOfflineQueue()
    }

    // MARK: - Recipe writes (Phase 3, v3 only)

    func updateRecipeName(recipeId: String, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            map.insert(key: "name", value: .string(trimmed), txn: txn)
        }
        try await updateCollectionEntry(recipeId: recipeId) { entryMap, txn in
            entryMap.insert(key: "name", value: .string(trimmed), txn: txn)
            entryMap.insert(key: "updatedAt", value: .string(Self.isoTimestamp()), txn: txn)
        }
    }

    func updateRecipeServings(recipeId: String, servings: Int) async throws {
        guard servings >= 1 else { throw RecipeEditError.invalidServings }
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            map.insert(key: "servings", value: .int(Int64(servings)), txn: txn)
        }
    }

    func updateRecipeColor(recipeId: String, color: String) async throws {
        let normalized = Self.normalizeColor(color)
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            map.insert(key: "color", value: .string(normalized), txn: txn)
        }
        if !currentCollectionKey.isEmpty {
            try await updateCollectionEntry(recipeId: recipeId) { entryMap, txn in
                entryMap.insert(key: "color", value: .string(normalized), txn: txn)
                entryMap.insert(key: "updatedAt", value: .string(Self.isoTimestamp()), txn: txn)
            }
        }
    }

    func addIngredient(recipeId: String, ingredient: IngredientData) async throws {
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            try Self.withIngredientsArray(in: map, txn: txn) { array in
                let index = array.length(txn: txn)
                array.insert(value: YrsInput.ingredientMap(ingredient), at: index, txn: txn)
                Self.renumberIngredientOrders(in: array, txn: txn)
            }
        }
    }

    func updateIngredient(recipeId: String, ingredient: IngredientData) async throws {
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            try Self.withIngredientsArray(in: map, txn: txn) { array in
                let len = array.length(txn: txn)
                for index in 0..<len {
                    array.withMap(at: index, txn: txn) { ingMap in
                        if ingMap.scalarString(key: "id", txn: txn) == ingredient.id {
                            Self.writeIngredient(ingMap, ingredient: ingredient, txn: txn)
                        }
                    }
                }
            }
        }
    }

    func removeIngredient(recipeId: String, ingredientId: String) async throws {
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            try Self.withIngredientsArray(in: map, txn: txn) { array in
                let len = array.length(txn: txn)
                for index in 0..<len {
                    if let id = array.withMap(at: index, txn: txn, { $0.scalarString(key: "id", txn: txn) }),
                       id == ingredientId {
                        array.remove(at: index, len: 1, txn: txn)
                        Self.renumberIngredientOrders(in: array, txn: txn)
                        break
                    }
                }
            }
        }
    }

    func moveIngredient(recipeId: String, fromIndex: Int, toIndex: Int) async throws {
        guard fromIndex != toIndex else { return }
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            try Self.withIngredientsArray(in: map, txn: txn) { array in
                let len = Int(array.length(txn: txn))
                guard fromIndex >= 0, toIndex >= 0, fromIndex < len, toIndex < len else { return }

                var moved: IngredientData?
                array.withMap(at: UInt32(fromIndex), txn: txn) { ingMap in
                    moved = Self.parseIngredientMap(ingMap, txn: txn, fallbackOrder: fromIndex + 1)
                }
                guard let moved else { return }

                array.remove(at: UInt32(fromIndex), len: 1, txn: txn)
                let insertAt = toIndex > fromIndex ? toIndex - 1 : toIndex
                array.insert(value: YrsInput.ingredientMap(moved), at: UInt32(insertAt), txn: txn)
                Self.renumberIngredientOrders(in: array, txn: txn)
            }
        }
    }

    func updateCollectionEntry(
        recipeId: String,
        _ body: (YrsMap, OpaquePointer) throws -> Void
    ) async throws {
        guard !currentCollectionKey.isEmpty else { return }
        let doc = try await getOrCreateDoc(key: currentCollectionKey)
        try await doc.withWriteTransaction { _, txn in
            guard let arrayBranch = ytype_get(txn, "recipes") else { return }
            let array = YrsArray(branch: arrayBranch)
            let len = array.length(txn: txn)
            for index in 0..<len {
                let matches = array.withMap(at: index, txn: txn) { map in
                    map.scalarString(key: "id", txn: txn) == recipeId
                } ?? false
                if matches {
                    try array.withMap(at: index, txn: txn) { map in
                        try body(map, txn)
                    }
                    break
                }
            }
        }
        await deliverPendingLocalUpdate(recipeId: "collection")
    }

    func updateNutrition(
        recipeId: String,
        calories: Double?,
        protein: Double?,
        fat: Double?,
        carbs: Double?
    ) async throws {
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            var fields: [(String, YrsInput)] = []
            if let calories { fields.append(("calories", .double(calories))) }
            if let protein { fields.append(("protein", .double(protein))) }
            if let fat { fields.append(("fat", .double(fat))) }
            if let carbs { fields.append(("carbs", .double(carbs))) }
            guard !fields.isEmpty else { return }

            if map.isNullOrMissing(key: "nutrition", txn: txn) {
                map.insert(key: "nutrition", value: .map(fields), txn: txn)
            } else {
                try map.withNestedMap(key: "nutrition", txn: txn) { nMap in
                    if let calories { nMap.insert(key: "calories", value: .double(calories), txn: txn) }
                    if let protein { nMap.insert(key: "protein", value: .double(protein), txn: txn) }
                    if let fat { nMap.insert(key: "fat", value: .double(fat), txn: txn) }
                    if let carbs { nMap.insert(key: "carbs", value: .double(carbs), txn: txn) }
                }
            }
        }
    }

    private func mutateRecipe(
        recipeId: String,
        _ body: (YrsMap, OpaquePointer) throws -> Void
    ) async throws {
        guard let userId = currentUserId else { throw RecipeEditError.documentNotLoaded }
        let key = "\(userId):recipe:\(recipeId)"
        let doc = try await getOrCreateDoc(key: key)

        let version = try await doc.withReadTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return nil as String? }
            return YrsMap(branch: mapBranch).string(key: "version", txn: txn)
        }
        guard RecipeEditPolicy.canEdit(version: version) else {
            throw RecipeEditError.legacyFormatReadOnly
        }

        suppressRecipeObserverDepth += 1
        defer { suppressRecipeObserverDepth -= 1 }

        try await doc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else {
                throw RecipeEditError.documentNotLoaded
            }
            let map = YrsMap(branch: mapBranch)
            try body(map, txn)
        }

        await deliverPendingLocalUpdate(recipeId: recipeId)
    }

    private func deliverPendingLocalUpdate(recipeId: String) async {
        guard let handler = onLocalRecipeUpdate,
              let userId = currentUserId else { return }
        let key: String
        if recipeId == "collection" {
            key = currentCollectionKey
        } else {
            key = "\(userId):recipe:\(recipeId)"
        }
        guard let doc = docs[key],
              let update = await doc.consumePendingLocalUpdates(),
              !update.isEmpty else { return }
        await handler(recipeId, update)
    }

    private func notifyRecipeChangedIfNeeded(recipeId: String) {
        guard suppressRecipeObserverDepth == 0 else { return }
        onRecipeChanged?(recipeId)
    }

    private static func normalizeColor(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), trimmed.count == 7 || trimmed.count == 4 else { return trimmed }
        return trimmed.uppercased()
    }

    private func installLocalUpdateBridge(key: String, doc: YrsDocument) async {
        _ = key
        _ = doc
    }

    private func installObservers(key: String, doc: YrsDocument) async {
        observerTokens.removeValue(forKey: key)

        if key.hasSuffix(":collection"), let handler = onCollectionChanged {
            if let token = try? await doc.addDeepObserver(rootKey: "recipes", handler: handler) {
                observerTokens[key] = token
            }
            return
        }

        guard let recipeId = recipeId(fromDocKey: key) else { return }
        let recipeHandler: @Sendable () -> Void = {
            Task { await self.handleRecipeObserverFire(recipeId: recipeId) }
        }
        if let token = try? await doc.addDeepObserver(rootKey: "recipe", handler: recipeHandler) {
            observerTokens[key] = token
        }
    }

    private func handleRecipeObserverFire(recipeId: String) {
        notifyRecipeChangedIfNeeded(recipeId: recipeId)
    }

    private func recipeId(fromDocKey key: String) -> String? {
        guard let range = key.range(of: ":recipe:") else { return nil }
        let id = String(key[range.upperBound...])
        return id.isEmpty ? nil : id
    }

    // ─── Parsing Helpers ─────────────────────────────────────────────────

    private func parseCollectionEntry(from map: YrsMap, txn: OpaquePointer) -> CollectionEntry {
        let id = map.scalarString(key: "id", txn: txn) ?? UUID().uuidString
        let deleted = map.bool(key: "deleted", txn: txn) ?? false

        return CollectionEntry(
            id: id,
            name: map.scalarString(key: "name", txn: txn) ?? "",
            color: map.scalarString(key: "color", txn: txn) ?? "#3b82f6",
            imageUrl: map.scalarString(key: "imageUrl", txn: txn),
            updatedAt: map.scalarString(key: "updatedAt", txn: txn) ?? "",
            deleted: deleted,
            isPinned: map.bool(key: "isPinned", txn: txn) ?? false
        )
    }

    private func parseRecipeData(from map: YrsMap, txn: OpaquePointer, recipeId: String) -> RecipeData {
        let versionString = map.scalarString(key: "version", txn: txn)
        let version = RecipeData.RecipeVersion.detect(versionString)

        return RecipeData(
            id: recipeId,
            name: readRecipeName(from: map, txn: txn),
            servings: map.int(key: "servings", txn: txn) ?? 1,
            color: map.scalarString(key: "color", txn: txn) ?? "#3b82f6",
            version: versionString ?? "v1",
            description: readDescription(from: map, txn: txn, version: version),
            ingredients: readIngredients(from: map, txn: txn, version: version),
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

    // ─── Version-Aware Field Readers ─────────────────────────────────────

    private func readRecipeName(from map: YrsMap, txn: OpaquePointer) -> String {
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
                    ingredients.append(Self.parseIngredientMap(ingMap, txn: txn, fallbackOrder: index + 1))
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
        if let parsed = try? map.withNestedMap(key: "nutrition", txn: txn, { nMap in
            NutritionData(
                calories: nMap.double(key: "calories", txn: txn),
                protein: nMap.double(key: "protein", txn: txn),
                fat: nMap.double(key: "fat", txn: txn),
                carbs: nMap.double(key: "carbs", txn: txn),
                extra: [:]
            )
        }) {
            return parsed
        }

        guard let val = map.value(key: "nutrition", txn: txn),
              val.tag == YrsValue.Y_JSON_STR,
              let json = val.stringValue else {
            return nil
        }
        return parseJSONNutrition(json)
    }

    // ─── JSON Fallback Parsers (v1) ──────────────────────────────────────

    private static func parseIngredientMap(
        _ ingMap: YrsMap,
        txn: OpaquePointer,
        fallbackOrder: Int
    ) -> IngredientData {
        let unit = ingMap.scalarString(key: "unit", txn: txn) ?? ""
        let amount = ingMap.scalarString(key: "amount", txn: txn) ?? ""
        let hasOriginal = !ingMap.isNullOrMissing(key: "originalAmount", txn: txn)
        let originalAmount = ingMap.scalarString(key: "originalAmount", txn: txn) ?? ""
        let isSeparator = ingMap.bool(key: "isSeparator", txn: txn) ?? false
        let hasQuantity = hasOriginal && !originalAmount.isEmpty

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
            weight: ingMap.double(key: "weight", txn: txn)
        )
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    /// Mutate `ingredients` while the parent `YOutput` from `ymap_get` stays alive (see `withNestedArray`).
    private static func withIngredientsArray<T>(
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

    private static func renumberIngredientOrders(in array: YrsArray, txn: OpaquePointer) {
        let len = array.length(txn: txn)
        for index in 0..<len {
            array.withMap(at: index, txn: txn) { ingMap in
                ingMap.insert(key: "order", value: .int(Int64(index + 1)), txn: txn)
            }
        }
    }

    private static func writeIngredient(_ ingMap: YrsMap, ingredient: IngredientData, txn: OpaquePointer) {
        ingMap.insert(key: "id", value: .string(ingredient.id), txn: txn)
        ingMap.insert(key: "name", value: .string(ingredient.name), txn: txn)
        ingMap.insert(key: "order", value: .int(Int64(ingredient.order)), txn: txn)
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

        Self.writeNutrition(ingMap, ingredient: ingredient, txn: txn)
    }

    private static func writeNutrition(_ ingMap: YrsMap, ingredient: IngredientData, txn: OpaquePointer) {
        writeOptionalDouble(ingMap, key: "calories", value: ingredient.calories, txn: txn)
        writeOptionalDouble(ingMap, key: "protein", value: ingredient.protein, txn: txn)
        writeOptionalDouble(ingMap, key: "fat", value: ingredient.fat, txn: txn)
        writeOptionalDouble(ingMap, key: "carbs", value: ingredient.carbs, txn: txn)
        writeOptionalDouble(ingMap, key: "weight", value: ingredient.weight, txn: txn)
    }

    private static func writeOptionalDouble(_ map: YrsMap, key: String, value: Double?, txn: OpaquePointer) {
        if let value {
            map.insert(key: key, value: .double(value), txn: txn)
        } else if !map.isNullOrMissing(key: key, txn: txn) {
            map.remove(key: key, txn: txn)
        }
    }

    private func parseJSONIngredients(_ json: String) -> [IngredientData] {
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
                weight: dict["weight"] as? Double ?? (dict["weight"] as? NSNumber)?.doubleValue
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
