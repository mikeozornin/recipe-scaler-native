import Foundation

/// Офлайн-очередь записи рецептов (GRDB `offline_sync_queue` через `YDocStore`).
actor OfflineWriteQueue {
    private let store: YDocStore

    init(store: YDocStore) {
        self.store = store
    }

    func enqueue(docKey: String, recipeId: String, yjsUpdate: Data) async throws {
        try await store.enqueueOfflineUpdate(docKey: docKey, recipeId: recipeId, yjsUpdate: yjsUpdate)
    }

    func fetchAll() async throws -> [OfflineSyncEntry] {
        try await store.fetchOfflineQueue()
    }

    /// Rows for one recipe only — avoids full-queue scan on debounced per-recipe paths (MIK-173).
    func fetch(forRecipeId recipeId: String) async throws -> [OfflineSyncEntry] {
        try await store.fetchOfflineQueue(forRecipeId: recipeId)
    }

    func deleteEntry(id: Int64) async throws {
        try await store.deleteOfflineEntry(id: id)
    }

    func clearAll() async throws {
        try await store.deleteAllOfflineQueue()
    }

    /// Remove queue rows that belong to another account (docKey prefix ≠ current user).
    @discardableResult
    func clearNotOwnedBy(userId: String) async throws -> Int {
        try await store.deleteOfflineQueueNotOwnedBy(userId: userId)
    }

    func clear(forRecipeId recipeId: String) async throws {
        try await store.deleteOfflineQueue(forRecipeId: recipeId)
    }

    func recipeIdsInQueue() async throws -> Set<String> {
        try await store.fetchOfflineQueueRecipeIds()
    }

    func deleteEntries(ids: [Int64]) async throws {
        try await store.deleteOfflineEntries(ids: ids)
    }

    /// Replace all queued rows for a recipe with one canonical update.
    func replaceForRecipe(docKey: String, recipeId: String, canonicalUpdate: Data) async throws {
        try await store.replaceOfflineQueueForRecipe(
            docKey: docKey,
            recipeId: recipeId,
            yjsUpdate: canonicalUpdate
        )
    }
}