import Foundation
import OSLog
import RecipeScalerCore
import YrsC

/// Manages Y.Doc instances and provides parsed domain models from CRDT data.
///
/// Thread-safe via actor isolation. Each Y.Doc is identified by its document key
/// (`{userId}:collection` or `{userId}:recipe:{recipeId}`).
actor DocumentManager {
    private var docs: [String: YrsDocument] = [:]
    private var observerTokens: [String: [YrsObserverToken]] = [:]
    private let store: YDocStore
    private static let logger = Logger(subsystem: "com.recipescaler.native", category: "DocumentManager")

    /// Test-only seam: when `true`, the next `applyUpdateToDoc` or
    /// `applyDescriptionEditorUpdate` call will throw a synthetic
    /// `YrsError.applyFailed` instead of invoking the yrs FFI. This lets
    /// regression tests drive the apply-failure catch path deterministically
    /// without depending on yrs' behavior on malformed input (which is not
    /// guaranteed to throw — it may no-op or, for some payloads, spin on
    /// varint parsing). Production code never sets this flag.
    #if DEBUG
    private var nextApplyUpdateShouldThrow = false
    func setNextApplyUpdateShouldThrow() {
        nextApplyUpdateShouldThrow = true
    }
    #endif

    private var onCollectionChanged: (@Sendable () -> Void)?
    private var onRecipeChanged: (@Sendable (String) -> Void)?
    var onShoppingChanged: (@Sendable () -> Void)?
    private var onLocalRecipeUpdate: (@Sendable (String, Data) async -> Void)?
    private var onDescriptionYjsUpdate: (@Sendable (String, Data) async -> Void)?
    var onLocalShoppingUpdate: (@Sendable (Data) async -> Void)?
    private var currentUserId: String?
    private var suppressRecipeObserverDepth = 0
    /// Debounced SQLite persist for hot description-editor paths (avoid per-keystroke full encode).
    private var snapshotPersistTasks: [String: Task<Void, Never>] = [:]
    /// Per-doc HTML serialization cache keyed by state vector. Invalidation
    /// happens implicitly via state-vector mismatch — if the doc was mutated
    /// (locally or via `applyUpdate`), the next read will see a fresh vector
    /// and recompute. Bounds memory by evicting entries past `maxHtmlCacheEntries`.
    private var htmlCache: [String: (stateVector: Data, html: String?)] = [:]
    private var plainTextCache: [String: (stateVector: Data, plainText: String)] = [:]
    private let maxHtmlCacheEntries = 64
    private static let snapshotPersistDebounceNs: UInt64 = 500_000_000

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

    func setDescriptionYjsUpdateHandler(_ handler: @escaping @Sendable (String, Data) async -> Void) {
        onDescriptionYjsUpdate = handler
    }

    func setShoppingHandlers(
        onChanged: @escaping @Sendable () -> Void,
        onLocalUpdate: @escaping @Sendable (Data) async -> Void
    ) {
        onShoppingChanged = onChanged
        onLocalShoppingUpdate = onLocalUpdate
    }

    func getCurrentUserId() -> String? {
        currentUserId
    }

    // ─── Document Lifecycle ──────────────────────────────────────────────

    func getOrCreateDoc(key: String) async throws -> YrsDocument {
        if let existing = docs[key] {
            return existing
        }

        let doc: YrsDocument
        if let snapshot = try? await store.loadSnapshot(docKey: key) {
            Self.logger.info("Loading doc \(UserIdFormatter.redactDocKey(key)) from SQLite snapshot (\(snapshot.state.count) bytes)")
            do {
                doc = try YrsDocument(state: snapshot.state)
            } catch {
                Self.logger.warning("Corrupted snapshot for \(UserIdFormatter.redactDocKey(key)), deleting and creating empty doc")
                try? await store.deleteSnapshot(docKey: key)
                doc = try YrsDocument()
            }
        } else {
            Self.logger.info("Creating empty doc for \(UserIdFormatter.redactDocKey(key))")
            doc = try YrsDocument()
        }

        docs[key] = doc
        if key.hasSuffix(":shoppingList") {
            await doc.ensureRootMap(named: ShoppingListConstants.rootMapKey)
        }
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
        #if DEBUG
        if nextApplyUpdateShouldThrow {
            nextApplyUpdateShouldThrow = false
            // Mirror what the catch block below does on a real apply failure:
            // evict in-memory state so the next getOrCreateDoc rebuilds from
            // the durable SQLite snapshot. The snapshot is preserved.
            docs.removeValue(forKey: key)
            observerTokens.removeValue(forKey: key)
            htmlCache.removeValue(forKey: key)
            plainTextCache.removeValue(forKey: key)
            throw YrsError.applyFailed(context: "test-forced apply failure")
        }
        #endif
        do {
            try await doc.applyUpdate(data)
        } catch {
            // yrs applyUpdate is atomic for malformed input, but transient FFI
            // errors could leave the in-memory doc in an unpredictable state.
            // Evict it so the next getOrCreateDoc rebuilds from the durable
            // SQLite snapshot, but DO NOT delete the snapshot itself — it may
            // contain unsynced local edits that we cannot reconstruct.
            // See plans/005-preserve-snapshot-on-apply-failure.md (finding #16).
            Self.logger.warning("applyUpdate failed for \(UserIdFormatter.redactDocKey(key)), evicting in-memory doc but preserving snapshot: \(error)")
            docs.removeValue(forKey: key)
            observerTokens.removeValue(forKey: key)
            htmlCache.removeValue(forKey: key)
            plainTextCache.removeValue(forKey: key)
            throw error
        }

        // State vector changed: any cached HTML is now stale. Drop it so the
        // next read recomputes (and re-caches with the new vector).
        htmlCache.removeValue(forKey: key)
        plainTextCache.removeValue(forKey: key)

        if let state = await doc.encodeStateAsUpdate() {
            try? await store.saveSnapshot(docKey: key, state: state, lastSyncedAt: lastSyncedAt)
        }
    }

    /// Replace an in-memory document with a full server snapshot (used on `document_loaded`).
    func replaceDocument(key: String, state: Data, lastSyncedAt: String? = nil) async throws {
        docs.removeValue(forKey: key)
        observerTokens.removeValue(forKey: key)
        htmlCache.removeValue(forKey: key)
        plainTextCache.removeValue(forKey: key)
        let doc = try YrsDocument(state: state)
        docs[key] = doc
        try? await store.saveSnapshot(docKey: key, state: state, lastSyncedAt: lastSyncedAt)
        await installObservers(key: key, doc: doc)
        Self.logger.info("Replaced doc \(UserIdFormatter.redactDocKey(key)) from server snapshot (\(state.count) bytes)")
    }

    func evictDoc(key: String) {
        docs.removeValue(forKey: key)
        observerTokens.removeValue(forKey: key)
        Self.logger.info("Evicted doc \(UserIdFormatter.redactDocKey(key)) from memory")
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
        let doc: YrsDocument
        if let existing = docs[key] {
            doc = existing
        } else if let restored = try? await getOrCreateDoc(key: key) {
            doc = restored
        } else {
            Self.logger.info("Recipe doc \(UserIdFormatter.redactDocKey(key)) not loaded")
            return nil
        }

        // Snapshot the state vector cheaply to look up the HTML cache before
        // paying for the XmlFragment tree walk.
        let cachedHTML: String?
        let currentSV: Data? = await doc.stateVector()
        if let currentSV,
           let cached = htmlCache[key],
           cached.stateVector == currentSV {
            cachedHTML = cached.html
        } else {
            cachedHTML = nil
        }

        let txnStart = CFAbsoluteTimeGetCurrent()
        var xmlSnapshot: String?
        let recipe: RecipeData? = try await doc.withReadTransaction { rawDoc, txn in
            guard let map = doc.recipeMap(txn: txn) else {
                Self.logger.warning("No 'recipe' Y.Map found in recipe doc \(UserIdFormatter.redactDocKey(key))")
                return nil as RecipeData?
            }
            let parsed = self.parseRecipeData(from: map, txn: txn, recipeId: recipeId)
            // Skip the expensive FFI tree walk when the cache is already valid
            // for this state vector.
            if cachedHTML == nil,
               RecipeData.RecipeVersion.detect(parsed.version) == .v3 {
                if let fragment = doc.xmlFragment(txn: txn, name: "description") {
                    xmlSnapshot = XmlFragmentToHTML.serializedFragment(from: fragment, txn: txn)
                }
            }
            return parsed
        }

        guard var recipe else { return nil }

        let computedHTML: String?
        if let cached = cachedHTML {
            computedHTML = cached
        } else if let xml = xmlSnapshot {
            computedHTML = XmlFragmentToHTML.html(fromSerializedXML: xml, ingredients: recipe.ingredients)
        } else {
            computedHTML = nil
        }

        // Update cache entry if state vector is known and we recomputed.
        if let currentSV, cachedHTML == nil {
            htmlCache[key] = (stateVector: currentSV, html: computedHTML)
            if htmlCache.count > maxHtmlCacheEntries {
                evictOldestHTMLCacheEntries()
            }
        }

        if let html = computedHTML, !html.isEmpty {
            recipe = recipe.replacing(description: html)
        }
        return recipe
    }

    /// Lightweight projection for recipe-list search: ingredients + description
    /// plain text only — no full `RecipeData`, no XmlFragment→HTML.
    func readSearchIndex(recipeId: String, userId: String) async throws -> RecipeSearchIndex? {
        let key = "\(userId):recipe:\(recipeId)"
        let doc: YrsDocument
        if let existing = docs[key] {
            doc = existing
        } else if let restored = try? await getOrCreateDoc(key: key) {
            doc = restored
        } else {
            return nil
        }

        let cachedPlainText: String?
        let currentSV: Data? = await doc.stateVector()
        if let currentSV,
           let cached = plainTextCache[key],
           cached.stateVector == currentSV {
            cachedPlainText = cached.plainText
        } else {
            cachedPlainText = nil
        }

        let index: RecipeSearchIndex? = try await doc.withReadTransaction { _, txn in
            guard let map = doc.recipeMap(txn: txn) else { return nil }
            let versionString = map.scalarString(key: "version", txn: txn)
            let version = RecipeData.RecipeVersion.detect(versionString)
            let ingredients = self.readSearchIngredients(from: map, txn: txn, version: version)

            let descriptionPlain: String
            if let cached = cachedPlainText {
                descriptionPlain = cached
            } else if version == .v3 {
                if let fragment = doc.xmlFragment(txn: txn, name: "description") {
                    descriptionPlain = XmlFragmentToPlainText.plainText(from: fragment, txn: txn)
                } else {
                    descriptionPlain = ""
                }
            } else if let raw = self.readDescription(from: map, txn: txn, version: version) {
                descriptionPlain = RecipeSearchUtils.plainText(fromDescriptionHTML: raw)
            } else {
                descriptionPlain = ""
            }

            return RecipeSearchIndex(
                id: recipeId,
                ingredientNames: ingredients.names,
                ingredientAmounts: ingredients.amounts,
                descriptionPlainText: descriptionPlain
            )
        }

        if let currentSV, cachedPlainText == nil, let index {
            plainTextCache[key] = (stateVector: currentSV, plainText: index.descriptionPlainText)
            if plainTextCache.count > maxHtmlCacheEntries {
                evictOldestPlainTextCacheEntries()
            }
        }

        return index
    }

    /// Cheap LRU-ish eviction: drop the first `n` over-capacity entries.
    /// `Dictionary` does not preserve insertion order, so this is effectively
    /// random eviction — acceptable for a best-effort cache where correctness
    /// is enforced by state-vector comparison, not by recency.
    private func evictOldestHTMLCacheEntries() {
        let drop = htmlCache.count - maxHtmlCacheEntries
        guard drop > 0 else { return }
        let keys = Array(htmlCache.keys.prefix(drop))
        for key in keys {
            htmlCache.removeValue(forKey: key)
        }
    }

    private func evictOldestPlainTextCacheEntries() {
        let drop = plainTextCache.count - maxHtmlCacheEntries
        guard drop > 0 else { return }
        let keys = Array(plainTextCache.keys.prefix(drop))
        for key in keys {
            plainTextCache.removeValue(forKey: key)
        }
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

    /// Drop in-memory docs after logout or account switch.
    func resetSession() {
        docs.removeAll()
        observerTokens.removeAll()
        currentUserId = nil
        currentCollectionKey = ""
    }

    // MARK: - Recipe writes (Phase 3, v3 only)

    func updateRecipeName(recipeId: String, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let touchedAt = Self.isoTimestamp()
        try await mutateRecipe(recipeId: recipeId, touchedAt: touchedAt) { map, txn in
            map.insert(key: "name", value: .string(trimmed), txn: txn)
        }
        try await updateCollectionEntry(recipeId: recipeId) { entryMap, txn in
            entryMap.insert(key: "name", value: .string(trimmed), txn: txn)
            entryMap.insert(key: "updatedAt", value: .string(touchedAt), txn: txn)
        }
    }

    func updateRecipeServings(recipeId: String, servings: Int) async throws {
        let capped = max(1, min(999, servings))
        // Web Yjs stores servings as JS number (float). Yrs `Y_JSON_INT` is not read by `normalizeServingsValue`.
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            map.insert(key: "servings", value: .double(Double(capped)), txn: txn)
        }
    }

    func updateRecipeIsPublic(recipeId: String, isPublic: Bool) async throws {
        // isPublic is recipe metadata (sharing), not a content edit.
        // It must be writable on v1/v2 too — web parity: web writes `recipeMap.set('isPublic', bool)` without a version gate.
        try await mutateRecipeMetadata(recipeId: recipeId) { map, txn in
            map.insert(key: "isPublic", value: .bool(isPublic), txn: txn)
        }
    }

    func updateRecipeImage(recipeId: String, imageUrl: String, aspectRatio: Double?) async throws {
        let trimmed = imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let touchedAt = Self.isoTimestamp()
        try await mutateRecipe(recipeId: recipeId, touchedAt: touchedAt) { map, txn in
            map.insert(key: "imageUrl", value: .string(trimmed), txn: txn)
            if let aspectRatio {
                map.insert(key: "imageAspectRatio", value: .double(aspectRatio), txn: txn)
            }
        }
        try await updateCollectionEntry(recipeId: recipeId) { entryMap, txn in
            entryMap.insert(key: "imageUrl", value: .string(trimmed), txn: txn)
            entryMap.insert(key: "updatedAt", value: .string(touchedAt), txn: txn)
        }
    }

    func clearRecipeImage(recipeId: String) async throws {
        let touchedAt = Self.isoTimestamp()
        try await mutateRecipe(recipeId: recipeId, touchedAt: touchedAt) { map, txn in
            _ = map.remove(key: "imageUrl", txn: txn)
            _ = map.remove(key: "imageAspectRatio", txn: txn)
        }
        try await updateCollectionEntry(recipeId: recipeId) { entryMap, txn in
            _ = entryMap.remove(key: "imageUrl", txn: txn)
            entryMap.insert(key: "updatedAt", value: .string(touchedAt), txn: txn)
        }
    }

    func updateRecipeColor(recipeId: String, color: String) async throws {
        let normalized = RecipeAccentColor.normalizedStored(color)
        let touchedAt = Self.isoTimestamp()
        try await mutateRecipe(recipeId: recipeId, touchedAt: touchedAt) { map, txn in
            map.insert(key: "color", value: .string(normalized), txn: txn)
        }
        if !currentCollectionKey.isEmpty {
            try await updateCollectionEntry(recipeId: recipeId) { entryMap, txn in
                entryMap.insert(key: "color", value: .string(normalized), txn: txn)
                entryMap.insert(key: "updatedAt", value: .string(touchedAt), txn: txn)
            }
        }
    }

    func addIngredient(recipeId: String, ingredient: IngredientData) async throws {
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            try Self.withIngredientsArray(in: map, txn: txn) { array in
                try Self.appendIngredient(ingredient, to: array, txn: txn)
                Self.renumberIngredientOrders(in: array, txn: txn)
            }
            map.insert(key: "nutritionOutdated", value: .bool(true), txn: txn)
        }
    }

    /// Batched variant of `addIngredient` for import paths that insert many
    /// ingredients at once. Performs a single write transaction, a single
    /// `renumberIngredientOrders` pass, and a single snapshot persist + deliver.
    /// Final merged Y.Doc state is identical to calling `addIngredient` per item.
    func addIngredients(recipeId: String, ingredients: [IngredientData]) async throws {
        guard !ingredients.isEmpty else { return }
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            try Self.withIngredientsArray(in: map, txn: txn) { array in
                for ingredient in ingredients {
                    try Self.appendIngredient(ingredient, to: array, txn: txn)
                }
                Self.renumberIngredientOrders(in: array, txn: txn)
            }
            map.insert(key: "nutritionOutdated", value: .bool(true), txn: txn)
        }
    }

    func updateIngredient(recipeId: String, ingredient: IngredientData, markNutritionOutdated: Bool = true) async throws {
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
            if markNutritionOutdated {
                map.insert(key: "nutritionOutdated", value: .bool(true), txn: txn)
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
            map.insert(key: "nutritionOutdated", value: .bool(true), txn: txn)
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
                try Self.insertIngredient(moved, into: array, at: UInt32(insertAt), txn: txn)
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
        await persistAndDeliver(recipeId: "collection", docKey: currentCollectionKey)
    }

    /// Merge queued offline Yjs updates into loaded docs and persist (restart before reconnect).
    func applyOfflineQueueToLocalDocs() async {
        guard let entries = try? await store.fetchOfflineQueue(), !entries.isEmpty else { return }
        let sorted = entries.sorted { $0.createdAt < $1.createdAt }
        for entry in sorted {
            do {
                try await applyUpdate(
                    key: entry.docKey,
                    data: entry.yjsUpdate,
                    suppressRecipeChangeNotification: true
                )
            } catch {
                Self.logger.warning("Failed to apply offline queue update for \(UserIdFormatter.redactDocKey(entry.docKey)): \(error)")
            }
        }
        Self.logger.info("Applied \(sorted.count) offline queue updates to local docs")
    }

    func persistSnapshot(docKey: String) async {
        guard let doc = docs[docKey],
              let state = await doc.encodeStateAsUpdate(),
              !state.isEmpty else { return }
        let lastSyncedAt = try? await store.loadSnapshot(docKey: docKey)?.lastSyncedAt
        do {
            try await store.saveSnapshot(docKey: docKey, state: state, lastSyncedAt: lastSyncedAt)
        } catch {
            Self.logger.warning("Failed to persist snapshot for \(UserIdFormatter.redactDocKey(docKey)): \(error)")
        }
    }

    /// Encode the document state ONCE, persist to SQLite, and forward the same
    /// bytes to the local-update handler. Avoids the double `encodeStateAsUpdate`
    /// that happens when calling `persistSnapshot` + `deliverPendingLocalUpdate`
    /// separately on every mutation.
    ///
    /// Also invalidates the HTML serialization cache for this docKey — after a
    /// mutation the state vector changes and any cached HTML is stale.
    private func persistAndDeliver(recipeId: String, docKey: String) async {
        guard let doc = docs[docKey] else { return }
        _ = await doc.consumePendingLocalUpdates()
        guard let state = await doc.encodeStateAsUpdate(), !state.isEmpty else {
            Self.logger.warning("No local Yjs update to sync for \(UserIdFormatter.redactDocKey(docKey))")
            return
        }
        // Drop any cached HTML/plain text so the next read sees the new state.
        htmlCache.removeValue(forKey: docKey)
        plainTextCache.removeValue(forKey: docKey)
        let lastSyncedAt = try? await store.loadSnapshot(docKey: docKey)?.lastSyncedAt
        do {
            try await store.saveSnapshot(docKey: docKey, state: state, lastSyncedAt: lastSyncedAt)
        } catch {
            Self.logger.warning("Failed to persist snapshot for \(UserIdFormatter.redactDocKey(docKey)): \(error)")
        }
        guard let handler = onLocalRecipeUpdate else { return }
        // Do not await: handler hops to @MainActor YjsSyncService while caller may be blocked on this actor.
        Task { await handler(recipeId, state) }
    }

    /// Schedule a debounced snapshot write (coalesces rapid description-editor keystrokes).
    func scheduleSnapshotPersist(docKey: String) {
        snapshotPersistTasks[docKey]?.cancel()
        snapshotPersistTasks[docKey] = Task {
            try? await Task.sleep(nanoseconds: Self.snapshotPersistDebounceNs)
            guard !Task.isCancelled else { return }
            await self.persistSnapshot(docKey: docKey)
        }
    }

    /// Flush any pending debounced snapshot immediately (e.g. before leaving edit mode).
    func flushScheduledSnapshotPersist(docKey: String) async {
        snapshotPersistTasks[docKey]?.cancel()
        snapshotPersistTasks[docKey] = nil
        await persistSnapshot(docKey: docKey)
    }

    // MARK: - Collection writes (008)

    private static let defaultNewRecipeColor = "oklch(0.65 0.25 270)"

    func setCollectionEntryPinned(recipeId: String, isPinned: Bool) async throws {
        let touchedAt = Self.isoTimestamp()
        try await updateCollectionEntry(recipeId: recipeId) { entryMap, txn in
            entryMap.insert(key: "isPinned", value: .bool(isPinned), txn: txn)
            entryMap.insert(key: "updatedAt", value: .string(touchedAt), txn: txn)
        }
    }

    func tombstoneCollectionEntry(recipeId: String) async throws {
        let touchedAt = Self.isoTimestamp()
        try await updateCollectionEntry(recipeId: recipeId) { entryMap, txn in
            entryMap.insert(key: "deleted", value: .bool(true), txn: txn)
            entryMap.insert(key: "updatedAt", value: .string(touchedAt), txn: txn)
        }
    }

    // MARK: - Collection folders (026 — collections parity)

    /// Read all active (non-deleted) folders from the collection doc,
    /// sorted by display name (case-insensitive, leading emoji ignored),
    /// tie-break by id. Mirrors web `readFolders`.
    func readFolders() async throws -> [RecipeFolder] {
        let doc = try await getOrCreateDoc(key: currentCollectionKey)
        let folders: [RecipeFolder] = try await doc.withReadTransaction { _, txn in
            guard let arrayBranch = ytype_get(txn, RecipeFolderConstants.foldersArrayKey) else {
                return []
            }
            let array = YrsArray(branch: arrayBranch)
            var result: [RecipeFolder] = []
            try array.forEachMap(txn: txn) { map in
                if let folder = Self.parseRecipeFolder(from: map, txn: txn) {
                    result.append(folder)
                }
            }
            return result
        }
        return RecipeFolder.sortedActive(folders)
    }

    /// Create a new folder Y.Map and append it to the `folders` array.
    /// Returns the new folder id. Web `createFolder` parity.
    @discardableResult
    func createFolder(name: String, color: String? = nil) async throws -> String {
        guard !currentCollectionKey.isEmpty else { throw RecipeEditError.documentNotLoaded }
        let id = UUID().uuidString
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedName = trimmedName.isEmpty
            ? RecipeFolderConstants.untitledFolderNameSentinel
            : trimmedName
        let resolvedColor = color?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalColor = (resolvedColor?.isEmpty == false)
            ? resolvedColor!
            : RecipeFolderConstants.defaultFolderColor
        let now = Self.isoTimestamp()

        let doc = try await getOrCreateDoc(key: currentCollectionKey)
        try await doc.withWriteTransaction { rawDoc, txn in
            let array: YrsArray
            if let branch = ytype_get(txn, RecipeFolderConstants.foldersArrayKey) {
                array = YrsArray(branch: branch)
            } else if let branch = yarray(rawDoc, RecipeFolderConstants.foldersArrayKey) {
                array = YrsArray(branch: branch)
            } else {
                throw RecipeEditError.documentNotLoaded
            }
            // Insert an empty map, then mutate its keys in place (same pattern
            // as `appendIngredient` — avoids the UTF-8 panic in `yinput_ymap`
            // when values reference transient buffers).
            let insertAt = array.length(txn: txn)
            array.insert(value: .map([]), at: insertAt, txn: txn)
            let wrote = array.withMap(at: insertAt, txn: txn) { map -> Bool in
                map.insert(key: "id", value: .string(id), txn: txn)
                map.insert(key: "name", value: .string(storedName), txn: txn)
                map.insert(key: "color", value: .string(finalColor), txn: txn)
                map.insert(key: "createdAt", value: .string(now), txn: txn)
                map.insert(key: "updatedAt", value: .string(now), txn: txn)
                map.insert(key: "deleted", value: .bool(false), txn: txn)
                return true
            }
            guard wrote == true else {
                throw RecipeEditError.documentNotLoaded
            }
        }
        await persistAndDeliver(recipeId: "collection", docKey: currentCollectionKey)
        return id
    }

    /// Resolve-or-create a folder by case-insensitive label.
    ///
    /// Used by spec 027 third-party import (US8): Paprika `categories` /
    /// Crouton `tags` map to folder labels. We reuse an existing non-deleted
    /// folder with the same label (case-insensitive, trimmed) when available,
    /// otherwise create a new one. Returns the folder id.
    @discardableResult
    func resolveOrCreateFolderId(label: String) async throws -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RecipeEditError.invalidInput
        }
        let existing = try await readFolders()
        let needle = trimmed.lowercased()
        if let match = existing.first(where: { !$0.deleted && $0.name.lowercased() == needle }) {
            return match.id
        }
        return try await createFolder(name: trimmed)
    }

    /// Rename a folder (and bump `updatedAt`).
    func renameFolder(id: String, name: String) async throws {
        try await mutateFolderEntry(id: id) { map, txn in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let stored = trimmed.isEmpty
                ? RecipeFolderConstants.untitledFolderNameSentinel
                : trimmed
            map.insert(key: "name", value: .string(stored), txn: txn)
        }
    }

    /// Update a folder accent color (and bump `updatedAt`). Web `setFolderColor` parity.
    func updateFolderColor(id: String, color: String) async throws {
        let normalized = RecipeAccentColor.normalizedStored(color)
        try await mutateFolderEntry(id: id) { map, txn in
            map.insert(key: "color", value: .string(normalized), txn: txn)
        }
    }

    /// Soft-delete a folder: tombstone + strip its id from every recipe
    /// entry's `folderIds` in one transaction (web `deleteFolder` parity).
    /// Recipes themselves are untouched — only membership.
    func deleteFolder(id: String) async throws {
        guard !currentCollectionKey.isEmpty else { throw RecipeEditError.documentNotLoaded }
        let now = Self.isoTimestamp()
        let doc = try await getOrCreateDoc(key: currentCollectionKey)
        try await doc.withWriteTransaction { rawDoc, txn in
            guard let foldersBranch = ytype_get(txn, RecipeFolderConstants.foldersArrayKey) else { return }
            let foldersArray = YrsArray(branch: foldersBranch)

            // Locate the target folder map (including soft-deleted).
            var folderIndex: UInt32? = nil
            let folderCount = foldersArray.length(txn: txn)
            for index in 0..<folderCount {
                let matches = foldersArray.withMap(at: index, txn: txn) { map -> Bool in
                    map.scalarString(key: "id", txn: txn) == id
                } ?? false
                if matches {
                    folderIndex = index
                    break
                }
            }
            guard let targetIndex = folderIndex else { return }

            foldersArray.withMap(at: targetIndex, txn: txn) { map in
                map.insert(key: "deleted", value: .bool(true), txn: txn)
                map.insert(key: "updatedAt", value: .string(now), txn: txn)
            }

            // Strip membership from every recipe entry in one transaction.
            guard let recipesBranch = ytype_get(txn, RecipeFolderConstants.recipesArrayKey) else { return }
            let recipesArray = YrsArray(branch: recipesBranch)
            let recipesCount = recipesArray.length(txn: txn)
            for recipeIndex in 0..<recipesCount {
                recipesArray.withMap(at: recipeIndex, txn: txn) { map in
                    let ids = map.stringArray(key: RecipeFolderConstants.folderIdsKey, txn: txn)
                    guard ids.contains(id) else { return }
                    let remaining = ids.filter { $0 != id }
                    Self.writeRecipeFolderIds(map: map, folderIds: remaining, txn: txn)
                    map.insert(key: "updatedAt", value: .string(now), txn: txn)
                }
            }
        }
        await persistAndDeliver(recipeId: "collection", docKey: currentCollectionKey)
    }

    /// Replace the set of folders a recipe belongs to.
    /// Validates ids against active folders, dedupes, and removes the key when empty.
    func setRecipeFolders(recipeId: String, folderIds: [String]) async throws {
        guard !currentCollectionKey.isEmpty else { throw RecipeEditError.documentNotLoaded }
        let doc = try await getOrCreateDoc(key: currentCollectionKey)
        // Validate ids against active folders before the write transaction.
        let activeFolderIds = try await activeFolderIdSet()
        let validIds = Self.normalizeFolderIds(folderIds, activeFolderIds: activeFolderIds)
        let now = Self.isoTimestamp()

        try await doc.withWriteTransaction { rawDoc, txn in
            guard let arrayBranch = ytype_get(txn, RecipeFolderConstants.recipesArrayKey) else { return }
            let array = YrsArray(branch: arrayBranch)
            let count = array.length(txn: txn)
            for index in 0..<count {
                let matches = array.withMap(at: index, txn: txn) { map -> Bool in
                    map.scalarString(key: "id", txn: txn) == recipeId
                } ?? false
                guard matches else { continue }
                array.withMap(at: index, txn: txn) { map in
                    Self.writeRecipeFolderIds(map: map, folderIds: validIds, txn: txn)
                    map.insert(key: "updatedAt", value: .string(now), txn: txn)
                }
                break
            }
        }
        await persistAndDeliver(recipeId: "collection", docKey: currentCollectionKey)
    }

    /// Set of active (non-deleted) folder ids — used to validate `folderIds` writes.
    private func activeFolderIdSet() async throws -> Set<String> {
        let doc = try await getOrCreateDoc(key: currentCollectionKey)
        return try await doc.withReadTransaction { _, txn in
            guard let arrayBranch = ytype_get(txn, RecipeFolderConstants.foldersArrayKey) else {
                return Set<String>()
            }
            let array = YrsArray(branch: arrayBranch)
            var ids = Set<String>()
            try array.forEachMap(txn: txn) { map in
                guard let id = map.scalarString(key: "id", txn: txn),
                      !id.isEmpty,
                      (map.bool(key: "deleted", txn: txn) ?? false) == false else {
                    return
                }
                ids.insert(id)
            }
            return ids
        }
    }

    /// Find a folder Y.Map by id (including soft-deleted) and run `body` on it.
    private func mutateFolderEntry(id: String, _ body: (YrsMap, OpaquePointer) throws -> Void) async throws {
        guard !currentCollectionKey.isEmpty else { throw RecipeEditError.documentNotLoaded }
        let now = Self.isoTimestamp()
        let doc = try await getOrCreateDoc(key: currentCollectionKey)
        try await doc.withWriteTransaction { _, txn in
            guard let arrayBranch = ytype_get(txn, RecipeFolderConstants.foldersArrayKey) else { return }
            let array = YrsArray(branch: arrayBranch)
            let count = array.length(txn: txn)
            for index in 0..<count {
                let matches = array.withMap(at: index, txn: txn) { map -> Bool in
                    map.scalarString(key: "id", txn: txn) == id
                } ?? false
                guard matches else { continue }
                try array.withMap(at: index, txn: txn) { map in
                    try body(map, txn)
                    map.insert(key: "updatedAt", value: .string(now), txn: txn)
                }
                break
            }
        }
        await persistAndDeliver(recipeId: "collection", docKey: currentCollectionKey)
    }

    /// Parse a folder Y.Map into `RecipeFolder`. Returns nil when the entry
    /// is missing an `id` or the id is empty (matches web `folderEntryToObject`).
    private static func parseRecipeFolder(from map: YrsMap, txn: OpaquePointer) -> RecipeFolder? {
        guard let id = map.scalarString(key: "id", txn: txn), !id.isEmpty else {
            return nil
        }
        let updatedAt = map.scalarString(key: "updatedAt", txn: txn) ?? Self.isoTimestamp()
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

    /// Dedupe and trim requested folder ids, keeping only those that refer to
    /// active (non-deleted) folders. Mirrors web `validateActiveCollectionIds`.
    private static func normalizeFolderIds(_ raw: [String], activeFolderIds: Set<String>) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in raw {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            guard activeFolderIds.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    /// Write the `folderIds` JSON-array value on a recipe entry map.
    /// Removes the key when the normalized list is empty (web `setRecipeFolderIds`).
    /// Important: this is a *replacement* of the whole array (last-write-wins per recipe).
    private static func writeRecipeFolderIds(map: YrsMap, folderIds: [String], txn: OpaquePointer) {
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

    /// Creates a v3 recipe document and collection entry (web `createRecipe` parity).
    func createRecipe(
        recipeId rawRecipeId: String = UUID().uuidString.lowercased(),
        name: String,
        color: String = defaultNewRecipeColor
    ) async throws -> String {
        let recipeId = rawRecipeId.lowercased()
        guard let userId = currentUserId else { throw RecipeEditError.documentNotLoaded }
        let touchedAt = Self.isoTimestamp()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? Bundle.currentLocalizedString("recipe.create.new") : trimmedName
        let normalizedColor = RecipeAccentColor.normalizedStored(color)

        try await appendCollectionEntryIfNotExists(
            recipeId: recipeId,
            name: displayName,
            color: normalizedColor,
            updatedAt: touchedAt
        )

        let recipeKey = "\(userId):recipe:\(recipeId)"
        let doc = try await getOrCreateDoc(key: recipeKey)
        await doc.ensureRecipeCreateRoots()
        try await doc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else {
                throw RecipeEditError.documentNotLoaded
            }
            let map = YrsMap(branch: mapBranch)
            map.insert(key: "id", value: .string(recipeId), txn: txn)
            map.insert(key: "name", value: .string(displayName), txn: txn)
            map.insert(key: "version", value: .string("v3"), txn: txn)
            map.insert(key: "servings", value: .double(1), txn: txn)
            map.insert(key: "color", value: .string(normalizedColor), txn: txn)
            map.insert(key: "createdAt", value: .string(touchedAt), txn: txn)
            map.insert(key: "updatedAt", value: .string(touchedAt), txn: txn)
            map.insert(key: "ingredients", value: .yarray([]), txn: txn)
            map.insert(key: "isPublic", value: .bool(false), txn: txn)
        }
        await deliverPendingLocalUpdate(recipeId: recipeId)
        return recipeId
    }

    /// Native format import (029): create v3 recipe from a full-featured draft.
    /// Handles color, servings, nutrition, description (as HTML → XmlFragment), dates,
    /// originalRecipe/Link, and ingredients with preserved amounts/units.
    func applyNativeRecipe(_ draft: NativeRecipe) async throws -> String {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty
            ? Bundle.currentLocalizedString("recipe.create.new")
            : trimmedName
        let color = draft.color ?? Self.defaultNewRecipeColor

        let recipeId = try await createRecipe(name: displayName, color: color)

        // Write rich fields
        try await mutateRecipe(recipeId: recipeId) { map, txn in
            if let servings = draft.servings, servings > 0 {
                map.insert(key: "servings", value: .double(servings), txn: txn)
            }
            if let desc = draft.description, !desc.isEmpty {
                map.insert(key: "description", value: .string(desc), txn: txn)
                map.insert(key: "hasSteps", value: .bool(true), txn: txn)
            }
            if let link = draft.originalRecipeLink?.trimmingCharacters(in: .whitespacesAndNewlines),
               !link.isEmpty {
                map.insert(key: "originalRecipeLink", value: .string(link), txn: txn)
            }
            if let source = draft.originalRecipe?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty {
                map.insert(key: "originalRecipe", value: .string(source), txn: txn)
            }
            if let createdAt = draft.createdAt, !createdAt.isEmpty {
                map.insert(key: "createdAt", value: .string(createdAt), txn: txn)
            }
            if let updatedAt = draft.updatedAt, !updatedAt.isEmpty {
                map.insert(key: "updatedAt", value: .string(updatedAt), txn: txn)
            }

            // Nutrition — write as nested Y.Map so readNutrition (which expects
            // a nested map at key "nutrition") round-trips correctly, including
            // optional `totalWeight`. Same pattern as updateNutrition below.
            if let nutrition = draft.nutrition {
                var fields: [(String, YrsInput)] = []
                if let cal = nutrition.calories {
                    fields.append(("calories", .double(cal)))
                }
                if let p = nutrition.protein {
                    fields.append(("protein", .double(p)))
                }
                if let f = nutrition.fat {
                    fields.append(("fat", .double(f)))
                }
                if let c = nutrition.carbs {
                    fields.append(("carbs", .double(c)))
                }
                if let tw = nutrition.totalWeight {
                    fields.append(("totalWeight", .double(tw)))
                }
                let outdated = nutrition.nutritionOutdated ?? true
                fields.append(("nutritionOutdated", .bool(outdated)))

                if map.isNullOrMissing(key: "nutrition", txn: txn) {
                    map.insert(key: "nutrition", value: .map(fields), txn: txn)
                } else {
                    try map.withNestedMap(key: "nutrition", txn: txn) { nMap in
                        for (key, value) in fields {
                            nMap.insert(key: key, value: value, txn: txn)
                        }
                    }
                }
                // Root-level flag is read by readNutrition as `rootOutdated`
                // (parity with server edit API).
                map.insert(key: "nutritionOutdated", value: .bool(outdated), txn: txn)
            }
        }

        // Write description as XmlFragment (v3 format) — parse the HTML into structured blocks
        // (paragraph / orderedList / listItem / heading / inline timer/ingredient/link runs) so
        // readers (XmlFragmentToHTML + RecipeDescriptionView) render interactive chips, not raw HTML.
        if let desc = draft.description, !desc.isEmpty {
            guard let userId = currentUserId else { throw RecipeEditError.documentNotLoaded }
            let key = "\(userId):recipe:\(recipeId)"
            let doc = try await getOrCreateDoc(key: key)
            let document = RecipeDescriptionParser.parse(desc)
            try await doc.withWriteTransaction { _, txn in
                if let fragment = doc.xmlFragment(txn: txn, name: "description") {
                    RecipeDescriptionXmlFragmentWriter.apply(
                        document: document,
                        to: fragment,
                        txn: txn
                    )
                }
            }
            await persistAndDeliver(recipeId: recipeId, docKey: key)
        }

        // Add ingredients (batched: single write-txn + single renumber pass + single persist/deliver)
        var collectedIngredients: [IngredientData] = []
        collectedIngredients.reserveCapacity(draft.ingredients.count)
        for (index, ingredient) in draft.ingredients.enumerated() {
            let trimmedName = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            let isSep = ingredient.isSeparator ?? false
            let order = ingredient.order ?? (index + 1)
            let originalAmount: Double? = ingredient.originalAmount
            let amountText: String? = ingredient.amountText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = ingredient.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Finding #15: prefer the numeric `originalAmount`; fall back to
            // optional `amountText` for non-numeric quantities.
            let hasQuantity: Bool
            let amountString: String
            if let oa = originalAmount {
                hasQuantity = true
                amountString = String(oa)
            } else if let text = amountText, !text.isEmpty {
                hasQuantity = true
                amountString = text
            } else {
                hasQuantity = false
                amountString = ""
            }

            let storedName = unit.isEmpty ? trimmedName : "\(trimmedName), \(unit)"
            collectedIngredients.append(
                IngredientData(
                    id: ingredient.id ?? UUID().uuidString,
                    name: storedName,
                    amount: amountString,
                    originalAmount: amountString,
                    unit: unit,
                    order: order,
                    isSeparator: isSep,
                    hasQuantity: hasQuantity
                )
            )
        }
        try await addIngredients(recipeId: recipeId, ingredients: collectedIngredients)

        return recipeId
    }

    /// Deterministic third-party import (027): create v3 recipe from parsed draft.
    func applyImportedRecipe(_ draft: ThirdPartyRecipeDraft) async throws -> String {
        // Resolve synthesized metadata blocks (Prep/Cook/duration/difficulty) into
        // localized paragraphs here, before the writer (which only handles
        // paragraph/heading/orderedListItem) and before hasSteps is computed.
        let localizedDescriptionBlocks = DescriptionBlockLocalizer.localize(draft.descriptionBlocks)

        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty
            ? Bundle.currentLocalizedString("recipe.create.new")
            : trimmedName

        let recipeId = try await createRecipe(name: displayName)

        try await mutateRecipe(recipeId: recipeId) { map, txn in
            map.insert(key: "servings", value: .double(Double(draft.servings)), txn: txn)
            if let source = draft.originalRecipe?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty {
                map.insert(key: "originalRecipe", value: .string(source), txn: txn)
            }
            if let link = draft.originalRecipeLink?.trimmingCharacters(in: .whitespacesAndNewlines),
               !link.isEmpty {
                map.insert(key: "originalRecipeLink", value: .string(link), txn: txn)
            }
            if !localizedDescriptionBlocks.isEmpty {
                map.insert(key: "hasSteps", value: .bool(true), txn: txn)
            }
        }

        var collectedIngredients: [IngredientData] = []
        collectedIngredients.reserveCapacity(draft.ingredients.count)
        for ingredient in draft.ingredients {
            let trimmedAmount = ingredient.amount.trimmingCharacters(in: .whitespacesAndNewlines)
            var unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            var amount = trimmedAmount
            if unit.isEmpty, !amount.isEmpty {
                let split = ThirdPartyIngredientAmountSplitter.split(amount)
                amount = split.amount
                unit = split.unit
            }
            let hasQuantity = !amount.isEmpty
            let trimmedName = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedName = unit.isEmpty ? trimmedName : "\(trimmedName), \(unit)"
            collectedIngredients.append(
                IngredientData(
                    id: UUID().uuidString,
                    name: storedName,
                    amount: amount,
                    originalAmount: amount,
                    unit: unit,
                    order: ingredient.order,
                    hasQuantity: hasQuantity
                )
            )
        }
        try await addIngredients(recipeId: recipeId, ingredients: collectedIngredients)

        if !localizedDescriptionBlocks.isEmpty {
            guard let userId = currentUserId else { throw RecipeEditError.documentNotLoaded }
            let key = "\(userId):recipe:\(recipeId)"
            let doc = try await getOrCreateDoc(key: key)
            try await doc.withWriteTransaction { _, txn in
                if let fragment = doc.xmlFragment(txn: txn, name: "description") {
                    DescriptionXmlFragmentWriter.apply(
                        blocks: localizedDescriptionBlocks,
                        to: fragment,
                        txn: txn
                    )
                }
            }
            await persistAndDeliver(recipeId: recipeId, docKey: key)
        }

        return recipeId
    }

    private func appendCollectionEntryIfNotExists(
        recipeId: String,
        name: String,
        color: String,
        updatedAt: String
    ) async throws {
        guard !currentCollectionKey.isEmpty else { return }
        let doc = try await getOrCreateDoc(key: currentCollectionKey)
        try await doc.withWriteTransaction { rawDoc, txn in
            let array: YrsArray
            if let branch = ytype_get(txn, RecipeFolderConstants.recipesArrayKey) {
                array = YrsArray(branch: branch)
            } else if let branch = yarray(rawDoc, RecipeFolderConstants.recipesArrayKey) {
                array = YrsArray(branch: branch)
            } else {
                throw RecipeEditError.documentNotLoaded
            }
            let len = array.length(txn: txn)
            for index in 0..<len {
                let matches = array.withMap(at: index, txn: txn) { map in
                    map.scalarString(key: "id", txn: txn) == recipeId
                } ?? false
                if matches { return }
            }
            let index = array.length(txn: txn)
            array.insert(value: .map([]), at: index, txn: txn)
            let wrote = array.withMap(at: index, txn: txn) { map -> Bool in
                map.insert(key: "id", value: .string(recipeId), txn: txn)
                map.insert(key: "name", value: .string(name), txn: txn)
                map.insert(key: "color", value: .string(color), txn: txn)
                map.insert(key: "updatedAt", value: .string(updatedAt), txn: txn)
                map.insert(key: "deleted", value: .bool(false), txn: txn)
                map.insert(key: "isPinned", value: .bool(false), txn: txn)
                return true
            }
            guard wrote == true else {
                throw RecipeEditError.documentNotLoaded
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
        touchedAt: String? = nil,
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

        let now = touchedAt ?? Self.isoTimestamp()
        try await doc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else {
                throw RecipeEditError.documentNotLoaded
            }
            let map = YrsMap(branch: mapBranch)
            try body(map, txn)
            map.insert(key: "updatedAt", value: .string(now), txn: txn)
        }

        await persistAndDeliver(recipeId: recipeId, docKey: key)
    }

    /// Writes a recipe metadata field (e.g. `isPublic`) without the v3-only edit gate.
    /// These fields exist on v1/v2/v3 and are safe to mutate regardless of `nativeEditingEnabled`.
    private func mutateRecipeMetadata(
        recipeId: String,
        touchedAt: String? = nil,
        _ body: (YrsMap, OpaquePointer) throws -> Void
    ) async throws {
        guard let userId = currentUserId else { throw RecipeEditError.documentNotLoaded }
        let key = "\(userId):recipe:\(recipeId)"
        let doc = try await getOrCreateDoc(key: key)

        suppressRecipeObserverDepth += 1
        defer { suppressRecipeObserverDepth -= 1 }

        let now = touchedAt ?? Self.isoTimestamp()
        try await doc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else {
                throw RecipeEditError.documentNotLoaded
            }
            let map = YrsMap(branch: mapBranch)
            try body(map, txn)
            map.insert(key: "updatedAt", value: .string(now), txn: txn)
        }

        await persistAndDeliver(recipeId: recipeId, docKey: key)
    }

    // MARK: - Description editor (006)

    /// Full recipe Y.Doc state for WKWebView Yjs bootstrap.
    func recipeDocumentState(recipeId: String) async throws -> Data {
        guard let userId = currentUserId else { throw RecipeEditError.documentNotLoaded }
        let key = "\(userId):recipe:\(recipeId)"
        let doc = try await getOrCreateDoc(key: key)
        guard let state = await doc.encodeStateAsUpdate() else {
            throw RecipeEditError.documentNotLoaded
        }
        return state
    }

    /// Applies incremental update from the embedded Yjs editor; forwards bytes to sync debouncer.
    func applyDescriptionEditorUpdate(
        recipeId: String,
        update: Data,
        forwardToSync: Bool = true
    ) async throws {
        guard !update.isEmpty else { return }
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

        // The WebView now emits incremental, identity-preserving 'reconcile' diffs
        // (description-editor-bridge.js). No oversized-update backstop needed: the
        // old >2048 guard existed only to block the full clearFragment()+reinsert
        // html-push that caused 5× duplication, which no longer happens.
        #if DEBUG
        if nextApplyUpdateShouldThrow {
            nextApplyUpdateShouldThrow = false
            docs.removeValue(forKey: key)
            observerTokens.removeValue(forKey: key)
            htmlCache.removeValue(forKey: key)
            plainTextCache.removeValue(forKey: key)
            throw YrsError.applyFailed(context: "test-forced apply failure (description editor)")
        }
        #endif
        do {
            try await doc.applyLocalUpdate(update)
        } catch {
            // Same reasoning as applyUpdateToDoc: evict in-memory state,
            // preserve SQLite snapshot. The description editor forwards
            // incremental yjs wire bytes, so a transient applyLocalUpdate
            // failure must not destroy the recipe snapshot.
            // See plans/005-preserve-snapshot-on-apply-failure.md (finding #16).
            Self.logger.warning("applyDescriptionEditorUpdate failed for \(UserIdFormatter.redactDocKey(key)), evicting in-memory doc but preserving snapshot: \(error)")
            docs.removeValue(forKey: key)
            observerTokens.removeValue(forKey: key)
            htmlCache.removeValue(forKey: key)
            plainTextCache.removeValue(forKey: key)
            throw error
        }
        // Description was just mutated; cached HTML/plain text for this recipe is stale.
        htmlCache.removeValue(forKey: key)
        plainTextCache.removeValue(forKey: key)
        // Hot path: debounce SQLite encode; network debouncer + flushPendingEdits persist on Done.
        scheduleSnapshotPersist(docKey: key)
        // Description renders in WebView during edit — skip recipe observer refresh per keystroke.

        _ = await doc.consumePendingLocalUpdates()
        // Forward yjs wire bytes from WebView — yrs re-encode breaks web XmlFragment parsing.
        if forwardToSync {
            await onDescriptionYjsUpdate?(recipeId, update)
        }
    }

    func pendingSyncByteCount(recipeId: String) async -> Int {
        guard let userId = currentUserId else { return 0 }
        let key = "\(userId):recipe:\(recipeId)"
        guard let doc = docs[key] else { return 0 }
        return await doc.pendingLocalUpdateByteCount()
    }

    func localSnapshotByteCount(recipeId: String) async -> Int {
        guard let userId = currentUserId else { return 0 }
        let key = "\(userId):recipe:\(recipeId)"
        return (try? await store.loadSnapshot(docKey: key))?.state.count ?? 0
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
        guard let doc = docs[key] else { return }
        _ = await doc.consumePendingLocalUpdates()
        let encodePayload = await doc.encodeStateAsUpdate()
        guard let update = encodePayload, !update.isEmpty else {
            Self.logger.warning("No local Yjs update to sync for \(UserIdFormatter.redactDocKey(key))")
            return
        }
        // Do not await: handler hops to @MainActor YjsSyncService while caller may be blocked on this actor.
        Task { await handler(recipeId, update) }
    }

    private func notifyRecipeChangedIfNeeded(recipeId: String) {
        guard suppressRecipeObserverDepth == 0 else { return }
        onRecipeChanged?(recipeId)
    }

    private func installObservers(key: String, doc: YrsDocument) async {
        observerTokens.removeValue(forKey: key)

        if key.hasSuffix(":collection"), let handler = onCollectionChanged {
            var tokens: [YrsObserverToken] = []
            // Deep-observe `recipes` (008) so pin/delete/name/folderIds changes fire.
            if let token = try? await doc.addDeepObserver(rootKey: RecipeFolderConstants.recipesArrayKey, handler: handler) {
                tokens.append(token)
            }
            // Also deep-observe `folders` (026) so rename/delete/create without
            // touching recipe entries still refreshes the UI.
            if let token = try? await doc.addDeepObserver(rootKey: RecipeFolderConstants.foldersArrayKey, handler: handler) {
                tokens.append(token)
            }
            if !tokens.isEmpty {
                observerTokens[key] = tokens
            }
            return
        }

        if key.hasSuffix(":shoppingList"), let handler = onShoppingChanged {
            if let token = try? await doc.addDeepObserver(rootKey: ShoppingListConstants.rootMapKey, handler: handler) {
                observerTokens[key] = [token]
            }
            return
        }

        guard let recipeId = recipeId(fromDocKey: key) else { return }
        let recipeHandler: @Sendable () -> Void = {
            Task { await self.handleRecipeObserverFire(recipeId: recipeId) }
        }
        if let token = try? await doc.addDeepObserver(rootKey: "recipe", handler: recipeHandler) {
            observerTokens[key] = [token]
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

    private func parseRecipeData(from map: YrsMap, txn: OpaquePointer, recipeId: String) -> RecipeData {
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

    private func readDescription(from map: YrsMap, txn: OpaquePointer, version: RecipeData.RecipeVersion) -> String? {
        switch version {
        case .v1:
            return map.string(key: "description", txn: txn)
        case .v2:
            if let text = map.withNestedText(key: "description", txn: txn, { $0.string(txn: txn) }) {
                return text
            }
            return map.string(key: "description", txn: txn)
        case .v3:
            // Filled from XmlFragment after the read transaction (see readRecipeData).
            if let text = map.withNestedText(key: "description", txn: txn, { $0.string(txn: txn) }) {
                return text
            }
            return map.string(key: "description", txn: txn)
        }
    }

    private struct SearchIngredientProjection {
        let names: [String]
        let amounts: [String]
    }

    private func readSearchIngredients(
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
                    let hasOriginal = !ingMap.isNullOrMissing(key: "originalAmount", txn: txn)
                    let originalAmount = ingMap.scalarString(key: "originalAmount", txn: txn) ?? ""
                    let amount = ingMap.scalarString(key: "amount", txn: txn) ?? ""
                    let hasQuantity = hasOriginal && !originalAmount.isEmpty
                    amounts.append(hasQuantity ? originalAmount : amount)
                }
                return SearchIngredientProjection(names: names, amounts: amounts)
            })
            return projection ?? SearchIngredientProjection(names: [], amounts: [])
        }
    }

    private func searchIngredientsFromJSON(_ json: String) -> SearchIngredientProjection {
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

    /// Inserts a new ingredient map via scalar `ymap_insert` calls (avoids nested `yinput_ymap` UTF-8 panic in yffi).
    private static func appendIngredient(
        _ ingredient: IngredientData,
        to array: YrsArray,
        txn: OpaquePointer
    ) throws {
        let index = array.length(txn: txn)
        try insertIngredient(ingredient, into: array, at: index, txn: txn)
    }

    private static func insertIngredient(
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
