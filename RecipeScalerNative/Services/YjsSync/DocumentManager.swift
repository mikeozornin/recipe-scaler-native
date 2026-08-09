import Foundation
import OSLog
import RecipeScalerCore
import YrsC

/// Immutable identity attached to work leaving a local Y.Doc. It remains
/// valid across a same-account reconnect, but is rejected after an account
/// switch or logout.
struct DocumentUpdateContext: Sendable, Equatable {
    let sessionId: UUID
    let userId: String
    let docKey: String
    let recipeId: String?
}

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

    private var onCollectionChanged: (@Sendable (DocumentUpdateContext) -> Void)?
    private var onRecipeChanged: (@Sendable (DocumentUpdateContext, String) -> Void)?
    var onShoppingChanged: (@Sendable (DocumentUpdateContext) -> Void)?
    private var onLocalRecipeUpdate: (@Sendable (DocumentUpdateContext, Data) async -> Void)?
    private var onDescriptionYjsUpdate: (@Sendable (DocumentUpdateContext, Data) async -> Void)?
    var onLocalShoppingUpdate: (@Sendable (DocumentUpdateContext, Data) async -> Void)?
    private var currentUserId: String?
    private var currentSessionId = UUID()
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
        onCollectionChanged: @escaping @Sendable (DocumentUpdateContext) -> Void,
        onRecipeChanged: @escaping @Sendable (DocumentUpdateContext, String) -> Void
    ) {
        self.onCollectionChanged = onCollectionChanged
        self.onRecipeChanged = onRecipeChanged
    }

    func setLocalUpdateHandler(_ handler: @escaping @Sendable (DocumentUpdateContext, Data) async -> Void) {
        onLocalRecipeUpdate = handler
    }

    func setDescriptionYjsUpdateHandler(_ handler: @escaping @Sendable (DocumentUpdateContext, Data) async -> Void) {
        onDescriptionYjsUpdate = handler
    }

    func setShoppingHandlers(
        onChanged: @escaping @Sendable (DocumentUpdateContext) -> Void,
        onLocalUpdate: @escaping @Sendable (DocumentUpdateContext, Data) async -> Void
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
        } else if key.hasSuffix(":collection") {
            // Pre-create root `Y.Array`s so writes never need to lazily register
            // them inside another active transaction (yrs FFI deadlock — MIK-155).
            await doc.ensureCollectionRoots()
        }
        await installObservers(key: key, doc: doc)
        return doc
    }

    func getDoc(key: String) -> YrsDocument? {
        return docs[key]
    }

    /// State vector of the in-memory doc, or empty `Data()` if the doc is not
    /// loaded. Used to compute `sync_step1.stateVector` without exposing the
    /// internal `YrsDocument`.
    func stateVectorForSync(key: String) async -> Data {
        if let doc = docs[key], let sv = await doc.stateVector() {
            return sv
        }
        return Data()
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
                result.append(RecipeYjsCodec.parseCollectionEntry(from: map, txn: txn))
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

    struct CollectionStructure: Equatable, Sendable {
        let liveRecipeIds: Set<String>
        let deletedRecipeIds: Set<String>

        var liveCount: Int { liveRecipeIds.count }
        var deletedCount: Int { deletedRecipeIds.count }
        var totalCount: Int { liveCount + deletedCount }
    }

    func readCollectionStructure(docKey: String? = nil) async throws -> CollectionStructure {
        let key = docKey ?? currentCollectionKey
        let doc = try await getOrCreateDoc(key: key)
        return try await doc.withReadTransaction { _, txn in
            guard let arrayBranch = ytype_get(txn, "recipes") else {
                return CollectionStructure(liveRecipeIds: [], deletedRecipeIds: [])
            }
            let array = YrsArray(branch: arrayBranch)
            var live: Set<String> = []
            var deleted: Set<String> = []
            try array.forEachMap(txn: txn) { map in
                guard let id = map.scalarString(key: "id", txn: txn), !id.isEmpty else { return }
                if map.bool(key: "deleted", txn: txn) == true {
                    deleted.insert(id)
                } else {
                    live.insert(id)
                }
            }
            return CollectionStructure(liveRecipeIds: live, deletedRecipeIds: deleted)
        }
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
            let parsed = RecipeYjsCodec.parseRecipeData(from: map, txn: txn, recipeId: recipeId)
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
            let ingredients = RecipeYjsCodec.readSearchIngredients(from: map, txn: txn, version: version)

            let descriptionPlain: String
            if let cached = cachedPlainText {
                descriptionPlain = cached
            } else if version == .v3 {
                if let fragment = doc.xmlFragment(txn: txn, name: "description") {
                    descriptionPlain = XmlFragmentToPlainText.plainText(from: fragment, txn: txn)
                } else {
                    descriptionPlain = ""
                }
            } else if let raw = RecipeYjsCodec.readDescription(from: map, txn: txn, version: version) {
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

    func setSession(userId: String, sessionId: UUID) {
        self.currentUserId = userId
        self.currentSessionId = sessionId
        self.currentCollectionKey = "\(userId):collection"
    }

    func setUserId(_ userId: String) {
        if currentUserId != userId {
            currentSessionId = UUID()
        }
        setSession(userId: userId, sessionId: currentSessionId)
    }

    func updateContext(docKey: String, recipeId: String?) -> DocumentUpdateContext? {
        guard let currentUserId else { return nil }
        return DocumentUpdateContext(
            sessionId: currentSessionId,
            userId: currentUserId,
            docKey: docKey,
            recipeId: recipeId
        )
    }

    /// A mutation may suspend while loading a Y.Doc or persisting a snapshot.
    /// Never let that old operation resume into a later account/session, even
    /// when the user switches away and back to the same account.
    func isCurrentContext(_ context: DocumentUpdateContext) -> Bool {
        guard currentUserId == context.userId, currentSessionId == context.sessionId else {
            return false
        }
        if context.recipeId == "collection" {
            return currentCollectionKey == context.docKey
        }
        return true
    }

    func clearOfflineQueueForAccountSwitch() async {
        try? await store.deleteAllOfflineQueue()
    }

    /// Drop in-memory docs after logout or account switch.
    func resetSession() {
        for task in snapshotPersistTasks.values {
            task.cancel()
        }
        snapshotPersistTasks.removeAll()
        docs.removeAll()
        observerTokens.removeAll()
        currentUserId = nil
        currentCollectionKey = ""
        currentSessionId = UUID()
    }

    // MARK: - Recipe writes (Phase 3, v3 only)

    func updateRecipeName(recipeId: String, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let touchedAt = Self.isoTimestamp()
        try await mutateRecipe(recipeId: recipeId, touchedAt: touchedAt) { writer in
            writer.setName(trimmed)
        }
        try await updateCollectionEntry(recipeId: recipeId, touchedAt: touchedAt) { writer in
            writer.setName(trimmed)
        }
    }

    func updateRecipeServings(recipeId: String, servings: Int) async throws {
        let capped = max(1, min(999, servings))
        try await mutateRecipe(recipeId: recipeId) { writer in
            writer.setServings(Double(capped))
        }
    }

    func updateRecipeIsPublic(recipeId: String, isPublic: Bool) async throws {
        // isPublic is recipe metadata (sharing), not a content edit.
        // It must be writable on v1/v2 too — web parity: web writes `recipeMap.set('isPublic', bool)` without a version gate.
        try await mutateRecipeMetadata(recipeId: recipeId) { writer in
            writer.setIsPublic(isPublic)
        }
    }

    func updateRecipeImage(recipeId: String, imageUrl: String, aspectRatio: Double?) async throws {
        let trimmed = imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let touchedAt = Self.isoTimestamp()
        try await mutateRecipe(recipeId: recipeId, touchedAt: touchedAt) { writer in
            writer.setImageUrl(trimmed)
            if let aspectRatio {
                writer.setImageAspectRatio(aspectRatio)
            }
        }
        try await updateCollectionEntry(recipeId: recipeId, touchedAt: touchedAt) { writer in
            writer.setImageUrl(trimmed)
        }
    }

    func clearRecipeImage(recipeId: String) async throws {
        let touchedAt = Self.isoTimestamp()
        try await mutateRecipe(recipeId: recipeId, touchedAt: touchedAt) { writer in
            writer.clearImageUrl()
        }
        try await updateCollectionEntry(recipeId: recipeId, touchedAt: touchedAt) { writer in
            writer.clearImageUrl()
        }
    }

    func updateRecipeColor(recipeId: String, color: String) async throws {
        let normalized = RecipeAccentColor.normalizedStored(color)
        let touchedAt = Self.isoTimestamp()
        try await mutateRecipe(recipeId: recipeId, touchedAt: touchedAt) { writer in
            writer.setColor(normalized)
        }
        if !currentCollectionKey.isEmpty {
            try await updateCollectionEntry(recipeId: recipeId, touchedAt: touchedAt) { writer in
                writer.setColor(normalized)
            }
        }
    }

    func addIngredient(recipeId: String, ingredient: IngredientData) async throws {
        try await mutateRecipe(recipeId: recipeId) { writer in
            try writer.appendIngredient(ingredient)
            writer.setNutritionOutdated(true)
        }
    }

    /// Batched variant of `addIngredient` for import paths that insert many
    /// ingredients at once. Performs a single write transaction, a single
    /// `renumberIngredientOrders` pass, and a single snapshot persist + deliver.
    /// Final merged Y.Doc state is identical to calling `addIngredient` per item.
    func addIngredients(recipeId: String, ingredients: [IngredientData]) async throws {
        guard !ingredients.isEmpty else { return }
        try await mutateRecipe(recipeId: recipeId) { writer in
            try writer.appendIngredients(ingredients)
            writer.setNutritionOutdated(true)
        }
    }

    func updateIngredient(recipeId: String, ingredient: IngredientData, markNutritionOutdated: Bool = true) async throws {
        try await mutateRecipe(recipeId: recipeId) { writer in
            try writer.updateIngredient(ingredient, markNutritionOutdated: markNutritionOutdated)
        }
    }

    func updateIngredientIllustrationBinding(
        recipeId: String,
        ingredientId: String,
        illustrationId: String?,
        pickerCleared: Bool
    ) async throws {
        try await updateIngredientIllustrationBindings(
            recipeId: recipeId,
            bindings: [(ingredientId, illustrationId, pickerCleared, nil)]
        )
    }

    func updateIngredientIllustrationBindings(
        recipeId: String,
        bindings: [(ingredientId: String, illustrationId: String?, pickerCleared: Bool, expectedName: String?)]
    ) async throws {
        guard !bindings.isEmpty else { return }
        try await mutateRecipe(recipeId: recipeId) { writer in
            try writer.updateIngredientIllustrationBindings(bindings)
        }
    }

    func removeIngredient(recipeId: String, ingredientId: String) async throws {
        try await mutateRecipe(recipeId: recipeId) { writer in
            try writer.removeIngredient(id: ingredientId)
        }
    }

    func moveIngredient(recipeId: String, fromIndex: Int, toIndex: Int) async throws {
        guard fromIndex != toIndex else { return }
        try await mutateRecipe(recipeId: recipeId) { writer in
            try writer.moveIngredient(from: fromIndex, to: toIndex)
        }
    }

    func updateCollectionEntry(
        recipeId: String,
        touchedAt: String? = nil,
        _ body: (inout CollectionEntryWriter) throws -> Void
    ) async throws {
        guard !currentCollectionKey.isEmpty else { return }
        let key = currentCollectionKey
        guard let context = updateContext(docKey: key, recipeId: "collection") else { return }
        let now = touchedAt ?? Self.isoTimestamp()
        let doc = try await getOrCreateDoc(key: key)
        guard isCurrentContext(context) else { return }
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
                        var writer = CollectionEntryWriter(map: map, txn: txn)
                        try body(&writer)
                        map.insert(key: "updatedAt", value: .string(now), txn: txn)
                    }
                    break
                }
            }
        }
        guard isCurrentContext(context) else { return }
        await persistAndDeliver(recipeId: "collection", docKey: key, context: context)
    }

    /// Merge queued offline Yjs updates into loaded docs and persist (restart before reconnect).
    func applyOfflineQueueToLocalDocs(userId: String? = nil) async {
        guard let entries = try? await store.fetchOfflineQueue(), !entries.isEmpty else { return }
        let ownedEntries: [OfflineSyncEntry]
        if let userId {
            let prefix = "\(userId):"
            ownedEntries = entries.filter { $0.docKey.hasPrefix(prefix) }
        } else {
            ownedEntries = entries
        }
        let sorted = ownedEntries.sorted { $0.createdAt < $1.createdAt }
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
    private func persistAndDeliver(
        recipeId: String,
        docKey: String,
        context: DocumentUpdateContext? = nil
    ) async {
        guard let capturedContext = context ?? updateContext(docKey: docKey, recipeId: recipeId),
              isCurrentContext(capturedContext),
              let doc = docs[docKey] else { return }
        _ = await doc.consumePendingLocalUpdates()
        guard isCurrentContext(capturedContext) else { return }
        guard let state = await doc.encodeStateAsUpdate(), !state.isEmpty else {
            Self.logger.warning("No local Yjs update to sync for \(UserIdFormatter.redactDocKey(docKey))")
            return
        }
        // Drop any cached HTML/plain text so the next read sees the new state.
        htmlCache.removeValue(forKey: docKey)
        plainTextCache.removeValue(forKey: docKey)
        let lastSyncedAt = try? await store.loadSnapshot(docKey: docKey)?.lastSyncedAt
        guard isCurrentContext(capturedContext) else { return }
        do {
            try await store.saveSnapshot(docKey: docKey, state: state, lastSyncedAt: lastSyncedAt)
        } catch {
            Self.logger.warning("Failed to persist snapshot for \(UserIdFormatter.redactDocKey(docKey)): \(error)")
        }
        guard isCurrentContext(capturedContext), let handler = onLocalRecipeUpdate else { return }
        // Do not await: handler hops to @MainActor YjsSyncService while caller may be blocked on this actor.
        Task { await handler(capturedContext, state) }
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
        try await updateCollectionEntry(recipeId: recipeId) { writer in
            writer.setIsPinned(isPinned)
        }
    }

    func tombstoneCollectionEntry(recipeId: String) async throws {
        try await updateCollectionEntry(recipeId: recipeId) { writer in
            writer.tombstone()
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
                if let folder = RecipeYjsCodec.parseRecipeFolder(from: map, txn: txn) {
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
        let key = currentCollectionKey
        guard let context = updateContext(docKey: key, recipeId: "collection") else {
            throw RecipeEditError.documentNotLoaded
        }
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

        let doc = try await getOrCreateDoc(key: key)
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
        try await doc.withWriteTransaction { rawDoc, txn in
            let array: YrsArray
            if let branch = ytype_get(txn, RecipeFolderConstants.foldersArrayKey) {
                array = YrsArray(branch: branch)
            } else {
                // Roots are pre-created in getOrCreateDoc (:collection) — if this
                // branch hits, the doc was opened through a code path that skipped
                // ensureCollectionRoots (e.g. legacy snapshot recovery). Fail loudly
                // rather than recurse into `yarray(rawDoc,)` here, which deadlocks
                // yrs FFI when another txn is active (MIK-155).
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
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
        await persistAndDeliver(recipeId: "collection", docKey: key, context: context)
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
        try await mutateFolderEntry(id: id) { writer in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let stored = trimmed.isEmpty
                ? RecipeFolderConstants.untitledFolderNameSentinel
                : trimmed
            writer.setName(stored)
        }
    }

    /// Update a folder accent color (and bump `updatedAt`). Web `setFolderColor` parity.
    func updateFolderColor(id: String, color: String) async throws {
        let normalized = RecipeAccentColor.normalizedStored(color)
        try await mutateFolderEntry(id: id) { writer in
            writer.setColor(normalized)
        }
    }

    /// Soft-delete a folder: tombstone + strip its id from every recipe
    /// entry's `folderIds` in one transaction (web `deleteFolder` parity).
    /// Recipes themselves are untouched — only membership.
    func deleteFolder(id: String) async throws {
        guard !currentCollectionKey.isEmpty else { throw RecipeEditError.documentNotLoaded }
        let key = currentCollectionKey
        guard let context = updateContext(docKey: key, recipeId: "collection") else {
            throw RecipeEditError.documentNotLoaded
        }
        let now = Self.isoTimestamp()
        let doc = try await getOrCreateDoc(key: key)
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
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
                    RecipeYjsWriter.writeRecipeFolderIds(map: map, folderIds: remaining, txn: txn)
                    map.insert(key: "updatedAt", value: .string(now), txn: txn)
                }
            }
        }
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
        await persistAndDeliver(recipeId: "collection", docKey: key, context: context)
    }

    /// Replace the set of folders a recipe belongs to.
    /// Validates ids against active folders, dedupes, and removes the key when empty.
    func setRecipeFolders(recipeId: String, folderIds: [String]) async throws {
        guard !currentCollectionKey.isEmpty else { throw RecipeEditError.documentNotLoaded }
        let key = currentCollectionKey
        guard let context = updateContext(docKey: key, recipeId: "collection") else {
            throw RecipeEditError.documentNotLoaded
        }
        let doc = try await getOrCreateDoc(key: key)
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
        // Validate ids against active folders before the write transaction.
        let activeFolderIds = try await activeFolderIdSet()
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
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
                    RecipeYjsWriter.writeRecipeFolderIds(map: map, folderIds: validIds, txn: txn)
                    map.insert(key: "updatedAt", value: .string(now), txn: txn)
                }
                break
            }
        }
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
        await persistAndDeliver(recipeId: "collection", docKey: key, context: context)
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
    private func mutateFolderEntry(id: String, _ body: (inout FolderEntryWriter) throws -> Void) async throws {
        guard !currentCollectionKey.isEmpty else { throw RecipeEditError.documentNotLoaded }
        let key = currentCollectionKey
        guard let context = updateContext(docKey: key, recipeId: "collection") else {
            throw RecipeEditError.documentNotLoaded
        }
        let now = Self.isoTimestamp()
        let doc = try await getOrCreateDoc(key: key)
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
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
                    var writer = FolderEntryWriter(map: map, txn: txn)
                    try body(&writer)
                    map.insert(key: "updatedAt", value: .string(now), txn: txn)
                }
                break
            }
        }
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
        await persistAndDeliver(recipeId: "collection", docKey: key, context: context)
    }

    /// Parse a folder Y.Map into `RecipeFolder`. Returns nil when the entry
    /// is missing an `id` or the id is empty (matches web `folderEntryToObject`).
    /// → Moved to `RecipeYjsCodec.parseRecipeFolder`.

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
    /// → Moved to `RecipeYjsWriter.writeRecipeFolderIds`.

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
        let recipeKey = "\(userId):recipe:\(recipeId)"
        guard let recipeContext = updateContext(docKey: recipeKey, recipeId: recipeId) else {
            throw RecipeEditError.documentNotLoaded
        }

        try await appendCollectionEntryIfNotExists(
            recipeId: recipeId,
            name: displayName,
            color: normalizedColor,
            updatedAt: touchedAt
        )
        guard isCurrentContext(recipeContext) else { throw RecipeEditError.documentNotLoaded }

        let doc = try await getOrCreateDoc(key: recipeKey)
        guard isCurrentContext(recipeContext) else { throw RecipeEditError.documentNotLoaded }
        await doc.ensureRecipeCreateRoots()
        guard isCurrentContext(recipeContext) else { throw RecipeEditError.documentNotLoaded }
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
        guard isCurrentContext(recipeContext) else { throw RecipeEditError.documentNotLoaded }
        await deliverPendingLocalUpdate(recipeId: recipeId, context: recipeContext)
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
        try await mutateRecipe(recipeId: recipeId) { writer in
            if let servings = draft.servings, servings > 0 {
                writer.setServings(servings)
            }
            if let desc = draft.description, !desc.isEmpty {
                writer.setDescription(desc)
                writer.setHasSteps(true)
            }
            if let link = draft.originalRecipeLink?.trimmingCharacters(in: .whitespacesAndNewlines),
               !link.isEmpty {
                writer.setOriginalRecipeLink(link)
            }
            if let source = draft.originalRecipe?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty {
                writer.setOriginalRecipe(source)
            }
            if let createdAt = draft.createdAt, !createdAt.isEmpty {
                writer.setCreatedAt(createdAt)
            }
            if let updatedAt = draft.updatedAt, !updatedAt.isEmpty {
                writer.setUpdatedAt(updatedAt)
            }

            // Nutrition — write as nested Y.Map so readNutrition (which expects
            // a nested map at key "nutrition") round-trips correctly, including
            // optional `totalWeight`. Same pattern as updateNutrition below.
            if let nutrition = draft.nutrition {
                writer.writeNutritionMap(
                    calories: nutrition.calories,
                    protein: nutrition.protein,
                    fat: nutrition.fat,
                    carbs: nutrition.carbs,
                    totalWeight: nutrition.totalWeight,
                    nutritionOutdated: nutrition.nutritionOutdated ?? true
                )
                // Root-level flag is read by readNutrition as `rootOutdated`
                // (parity with server edit API).
                writer.setNutritionOutdated(nutrition.nutritionOutdated ?? true)
            }
        }

        // Write description as XmlFragment (v3 format) — parse the HTML into structured blocks
        // (paragraph / orderedList / listItem / heading / inline timer/ingredient/link runs) so
        // readers (XmlFragmentToHTML + RecipeDescriptionView) render interactive chips, not raw HTML.
        if let desc = draft.description, !desc.isEmpty {
            guard let userId = currentUserId else { throw RecipeEditError.documentNotLoaded }
            let key = "\(userId):recipe:\(recipeId)"
            guard let context = updateContext(docKey: key, recipeId: recipeId) else {
                throw RecipeEditError.documentNotLoaded
            }
            let doc = try await getOrCreateDoc(key: key)
            guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
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
            guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
            await persistAndDeliver(recipeId: recipeId, docKey: key, context: context)
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

        try await mutateRecipe(recipeId: recipeId) { writer in
            writer.setServings(Double(draft.servings))
            if let source = draft.originalRecipe?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty {
                writer.setOriginalRecipe(source)
            }
            if let link = draft.originalRecipeLink?.trimmingCharacters(in: .whitespacesAndNewlines),
               !link.isEmpty {
                writer.setOriginalRecipeLink(link)
            }
            if !localizedDescriptionBlocks.isEmpty {
                writer.setHasSteps(true)
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
            guard let context = updateContext(docKey: key, recipeId: recipeId) else {
                throw RecipeEditError.documentNotLoaded
            }
            let doc = try await getOrCreateDoc(key: key)
            guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
            try await doc.withWriteTransaction { _, txn in
                if let fragment = doc.xmlFragment(txn: txn, name: "description") {
                    DescriptionXmlFragmentWriter.apply(
                        blocks: localizedDescriptionBlocks,
                        to: fragment,
                        txn: txn
                    )
                }
            }
            guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
            await persistAndDeliver(recipeId: recipeId, docKey: key, context: context)
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
        let key = currentCollectionKey
        guard let context = updateContext(docKey: key, recipeId: "collection") else { return }
        let doc = try await getOrCreateDoc(key: key)
        guard isCurrentContext(context) else { return }
        try await doc.withWriteTransaction { rawDoc, txn in
            let array: YrsArray
            if let branch = ytype_get(txn, RecipeFolderConstants.recipesArrayKey) {
                array = YrsArray(branch: branch)
            } else {
                // Roots are pre-created in getOrCreateDoc (:collection) — see MIK-155.
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
        guard isCurrentContext(context) else { return }
        await deliverPendingLocalUpdate(recipeId: "collection", context: context)
    }

    func updateNutrition(
        recipeId: String,
        calories: Double?,
        protein: Double?,
        fat: Double?,
        carbs: Double?
    ) async throws {
        try await mutateRecipe(recipeId: recipeId) { writer in
            writer.writeNutritionMap(
                calories: calories,
                protein: protein,
                fat: fat,
                carbs: carbs
            )
        }
    }

    private func mutateRecipe(
        recipeId: String,
        touchedAt: String? = nil,
        _ body: (inout RecipeMapWriter) throws -> Void
    ) async throws {
        guard let userId = currentUserId else { throw RecipeEditError.documentNotLoaded }
        let key = "\(userId):recipe:\(recipeId)"
        guard let context = updateContext(docKey: key, recipeId: recipeId) else {
            throw RecipeEditError.documentNotLoaded
        }
        let doc = try await getOrCreateDoc(key: key)
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }

        let version = try await doc.withReadTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return nil as String? }
            return YrsMap(branch: mapBranch).string(key: "version", txn: txn)
        }
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
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
            var writer = RecipeMapWriter(map: YrsMap(branch: mapBranch), txn: txn)
            try body(&writer)
            writer.map.insert(key: "updatedAt", value: .string(now), txn: txn)
        }

        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
        await persistAndDeliver(recipeId: recipeId, docKey: key, context: context)
    }

    /// Writes a recipe metadata field (e.g. `isPublic`) without the v3-only edit gate.
    /// These fields exist on v1/v2/v3 and are safe to mutate regardless of `nativeEditingEnabled`.
    private func mutateRecipeMetadata(
        recipeId: String,
        touchedAt: String? = nil,
        _ body: (inout RecipeMapWriter) throws -> Void
    ) async throws {
        guard let userId = currentUserId else { throw RecipeEditError.documentNotLoaded }
        let key = "\(userId):recipe:\(recipeId)"
        guard let context = updateContext(docKey: key, recipeId: recipeId) else {
            throw RecipeEditError.documentNotLoaded
        }
        let doc = try await getOrCreateDoc(key: key)
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }

        suppressRecipeObserverDepth += 1
        defer { suppressRecipeObserverDepth -= 1 }

        let now = touchedAt ?? Self.isoTimestamp()
        try await doc.withWriteTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else {
                throw RecipeEditError.documentNotLoaded
            }
            var writer = RecipeMapWriter(map: YrsMap(branch: mapBranch), txn: txn)
            try body(&writer)
            writer.map.insert(key: "updatedAt", value: .string(now), txn: txn)
        }

        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
        await persistAndDeliver(recipeId: recipeId, docKey: key, context: context)
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
        guard let context = updateContext(docKey: key, recipeId: recipeId) else {
            throw RecipeEditError.documentNotLoaded
        }
        let doc = try await getOrCreateDoc(key: key)
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }

        let version = try await doc.withReadTransaction { _, txn in
            guard let mapBranch = ytype_get(txn, "recipe") else { return nil as String? }
            return YrsMap(branch: mapBranch).string(key: "version", txn: txn)
        }
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
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
        guard isCurrentContext(context) else { throw RecipeEditError.documentNotLoaded }
        // Description was just mutated; cached HTML/plain text for this recipe is stale.
        htmlCache.removeValue(forKey: key)
        plainTextCache.removeValue(forKey: key)
        // Hot path: debounce SQLite encode; network debouncer + flushPendingEdits persist on Done.
        scheduleSnapshotPersist(docKey: key)
        // Description renders in WebView during edit — skip recipe observer refresh per keystroke.

        _ = await doc.consumePendingLocalUpdates()
        // Forward yjs wire bytes from WebView — yrs re-encode breaks web XmlFragment parsing.
        if forwardToSync,
           isCurrentContext(context),
           let handler = onDescriptionYjsUpdate {
            await handler(context, update)
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

    private func deliverPendingLocalUpdate(
        recipeId: String,
        context: DocumentUpdateContext? = nil
    ) async {
        guard let handler = onLocalRecipeUpdate else { return }
        let capturedContext: DocumentUpdateContext
        if let context {
            capturedContext = context
        } else {
            guard let userId = currentUserId else { return }
            let key = recipeId == "collection"
                ? currentCollectionKey
                : "\(userId):recipe:\(recipeId)"
            guard let currentContext = updateContext(docKey: key, recipeId: recipeId) else { return }
            capturedContext = currentContext
        }
        guard isCurrentContext(capturedContext), let doc = docs[capturedContext.docKey] else { return }
        _ = await doc.consumePendingLocalUpdates()
        guard isCurrentContext(capturedContext) else { return }
        let encodePayload = await doc.encodeStateAsUpdate()
        guard let update = encodePayload, !update.isEmpty else {
            Self.logger.warning("No local Yjs update to sync for \(UserIdFormatter.redactDocKey(capturedContext.docKey))")
            return
        }
        // Do not await: handler hops to @MainActor YjsSyncService while caller may be blocked on this actor.
        guard isCurrentContext(capturedContext) else { return }
        Task { await handler(capturedContext, update) }
    }

    private func notifyRecipeChangedIfNeeded(
        context: DocumentUpdateContext,
        recipeId: String
    ) {
        guard suppressRecipeObserverDepth == 0 else { return }
        onRecipeChanged?(context, recipeId)
    }

    private func installObservers(key: String, doc: YrsDocument) async {
        observerTokens.removeValue(forKey: key)

        if key.hasSuffix(":collection"),
           let handler = onCollectionChanged,
           let context = updateContext(docKey: key, recipeId: "collection") {
            var tokens: [YrsObserverToken] = []
            let contextHandler: @Sendable () -> Void = { handler(context) }
            // Deep-observe `recipes` (008) so pin/delete/name/folderIds changes fire.
            if let token = try? await doc.addDeepObserver(rootKey: RecipeFolderConstants.recipesArrayKey, handler: contextHandler) {
                tokens.append(token)
            }
            // Also deep-observe `folders` (026) so rename/delete/create without
            // touching recipe entries still refreshes the UI.
            if let token = try? await doc.addDeepObserver(rootKey: RecipeFolderConstants.foldersArrayKey, handler: contextHandler) {
                tokens.append(token)
            }
            if !tokens.isEmpty {
                observerTokens[key] = tokens
            }
            return
        }

        if key.hasSuffix(":shoppingList"),
           let handler = onShoppingChanged,
           let context = updateContext(docKey: key, recipeId: nil) {
            let contextHandler: @Sendable () -> Void = { handler(context) }
            if let token = try? await doc.addDeepObserver(rootKey: ShoppingListConstants.rootMapKey, handler: contextHandler) {
                observerTokens[key] = [token]
            }
            return
        }

        guard let recipeId = recipeId(fromDocKey: key) else { return }
        guard let context = updateContext(docKey: key, recipeId: recipeId) else { return }
        let recipeHandler: @Sendable () -> Void = {
            Task { await self.handleRecipeObserverFire(context: context, recipeId: recipeId) }
        }
        if let token = try? await doc.addDeepObserver(rootKey: "recipe", handler: recipeHandler) {
            observerTokens[key] = [token]
        }
    }

    private func handleRecipeObserverFire(context: DocumentUpdateContext, recipeId: String) {
        notifyRecipeChangedIfNeeded(context: context, recipeId: recipeId)
    }

    private func recipeId(fromDocKey key: String) -> String? {
        guard let range = key.range(of: ":recipe:") else { return nil }
        let id = String(key[range.upperBound...])
        return id.isEmpty ? nil : id
    }

    // ─── Parsing Helpers → moved to RecipeYjsCodec ─────────────────────

    // All private parser / reader helpers (parseCollectionEntry, parseRecipeData,
    // readRecipeName, readDescription, readIngredients, readNutrition,
    // readSearchIngredients, searchIngredientsFromJSON, parseIngredientMap,
    // parseJSONIngredients, parseJSONNutrition, SearchIngredientProjection) now
    // live in `RecipeYjsCodec` so they can be shared with `RecipeReader` (Discover).

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // parseJSONIngredients / parseJSONNutrition → moved to RecipeYjsCodec.
    // withIngredientsArray / appendIngredient / insertIngredient /
    // renumberIngredientOrders / writeIngredient / writeNutrition /
    // writeOptionalDouble / writeRecipeFolderIds → moved to RecipeYjsWriter.
}
