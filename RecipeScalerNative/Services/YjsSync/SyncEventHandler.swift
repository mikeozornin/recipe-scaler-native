import Foundation

import SocketIO

/// Handles all Socket.IO events for Y.Doc synchronization.
///
/// Parses incoming events, converts binary payloads, and delegates
/// to callbacks provided by YjsSyncService.
final class SyncEventHandler {

    // MARK: - Callbacks (set by YjsSyncService)

    /// Called when a full document state is loaded from the server.
    var onDocumentLoaded: ((String, Data, String?) -> Void)?

    /// Called when batch documents are loaded.
    var onDocumentsLoaded: ([(String, Data, String?)]) -> Void = { _ in }

    /// Called when an incremental update arrives for a recipe.
    var onRecipeUpdated: ((String, Data) -> Void)?

    /// Called when an incremental update arrives for the collection.
    var onCollectionUpdated: ((Data) -> Void)?

    /// Called when an incremental update arrives for the shopping list.
    var onShoppingListUpdated: ((Data) -> Void)?

    /// Called on sync error.
    ///
    /// - Parameters in closure: `(code, message, recipeId)`
    ///   - `code`: typed `SyncErrorCode` resolved from `payload["code"]` (future)
    ///     or from the legacy English `payload["error"]` substring.
    ///   - `message`: raw `payload["error"]` string (kept for logging only —
    ///     never reaches the UI directly).
    ///   - `recipeId`: optional related recipe id.
    var onSyncError: ((SyncErrorCode, String, String?) -> Void)?

    /// Called when sync is confirmed (recipeId, lastSyncedAt).
    var onSyncConfirmed: ((String, String?) -> Void)?

    // MARK: - Event Registration

    /// Register all Socket.IO event handlers on the given client.
    func registerHandlers(on client: SocketIOClient) {
        client.on("document_loaded") { [weak self] data, _ in
            self?.handleDocumentLoaded(data)
        }

        client.on("documents_loaded") { [weak self] data, _ in
            self?.handleDocumentsLoaded(data)
        }

        client.on("recipe_updated") { [weak self] data, _ in
            self?.handleRecipeUpdated(data)
        }

        client.on("collection_updated") { [weak self] data, _ in
            self?.handleCollectionUpdated(data)
        }

        client.on("shopping_list_updated") { [weak self] data, _ in
            self?.handleShoppingListUpdated(data)
        }

        client.on("sync_confirmed") { [weak self] data, _ in
            self?.handleSyncConfirmed(data)
        }

        client.on("sync_error") { [weak self] data, _ in
            self?.handleSyncError(data)
        }
    }

    // MARK: - Handlers

    private func handleDocumentLoaded(_ data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            AppLog.error(.sync, "document_loaded: invalid payload format")
            return
        }

        let documentKind = payload["documentKind"] as? String
        // Server returns recipeId=nil for collection document (we send {} without recipeId)
        let recipeId: String
        if documentKind == ShoppingListConstants.documentKind {
            recipeId = ShoppingListConstants.offlineRecipeId
        } else {
            recipeId = collectionRecipeId(from: payload["recipeId"])
        }
        guard let stateData = YjsPayloadBytes.data(from: payload["yjsState"]) else {
            AppLog.error(.sync, "document_loaded: missing or invalid yjsState for \(recipeId)")
            return
        }
        let lastSyncedAt = payload["lastSyncedAt"] as? String

        AppLog.info(.sync, "document_loaded: \(recipeId), \(stateData.count) bytes")
        if recipeId == "collection" {
            AppLog.info(.sync, "collection document_loaded: \(stateData.count) bytes")
        }
        onDocumentLoaded?(recipeId, stateData, lastSyncedAt)
    }

    private func handleDocumentsLoaded(_ data: [Any]) {
        guard let payload = data.first as? [String: Any],
              let documents = payload["documents"] as? [[String: Any]] else {
            AppLog.error(.sync, "documents_loaded: invalid payload format")
            return
        }

        var results: [(String, Data, String?)] = []
        for doc in documents {
            let recipeId = collectionRecipeId(from: doc["recipeId"])
            guard let stateData = YjsPayloadBytes.data(from: doc["yjsState"]) else {
                AppLog.notice(.sync, "documents_loaded: skipping doc with missing yjsState for \(recipeId)")
                continue
            }
            let lastSyncedAt = doc["lastSyncedAt"] as? String
            results.append((recipeId, stateData, lastSyncedAt))
        }

        AppLog.info(.sync, "documents_loaded: \(results.count) documents")
        onDocumentsLoaded(results)
    }

    private func handleRecipeUpdated(_ data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            AppLog.error(.sync, "recipe_updated: invalid payload format")
            return
        }

        let recipeId = payload["recipeId"] as? String ?? "unknown"
        guard let updateData = YjsPayloadBytes.data(from: payload["yjsUpdate"]) else {
            AppLog.notice(.sync, "recipe_updated: missing yjsUpdate for \(recipeId)")
            return
        }

        AppLog.debug(.sync, "recipe_updated: \(recipeId), \(updateData.count) bytes")
        onRecipeUpdated?(recipeId, updateData)
    }

    private func handleCollectionUpdated(_ data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            AppLog.error(.sync, "collection_updated: invalid payload format")
            return
        }

        guard let updateData = YjsPayloadBytes.data(from: payload["yjsUpdate"]) else {
            AppLog.notice(.sync, "collection_updated: missing yjsUpdate")
            return
        }

        AppLog.debug(.sync, "collection_updated: \(updateData.count) bytes")
        onCollectionUpdated?(updateData)
    }

    private func handleShoppingListUpdated(_ data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            AppLog.error(.sync, "shopping_list_updated: invalid payload format")
            return
        }

        guard let updateData = YjsPayloadBytes.data(from: payload["yjsUpdate"]) else {
            AppLog.notice(.sync, "shopping_list_updated: missing yjsUpdate")
            return
        }

        AppLog.debug(.sync, "shopping_list_updated: \(updateData.count) bytes")
        onShoppingListUpdated?(updateData)
    }

    private func handleSyncConfirmed(_ data: [Any]) {
        guard let payload = data.first as? [String: Any] else { return }
        let documentKind = payload["documentKind"] as? String
        let recipeId: String
        if documentKind == ShoppingListConstants.documentKind {
            recipeId = ShoppingListConstants.offlineRecipeId
        } else {
            recipeId = payload["recipeId"] as? String ?? "unknown"
        }
        let lastSyncedAt = payload["lastSyncedAt"] as? String
        AppLog.debug(.sync, "sync_confirmed: \(recipeId)")
        onSyncConfirmed?(recipeId, lastSyncedAt)
    }

    private func handleSyncError(_ data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            AppLog.error(.sync, "sync_error: invalid payload format")
            return
        }

        let message = payload["error"] as? String ?? "Unknown sync error"
        let codeValue = payload["code"] as? String
        let recipeId = payload["recipeId"] as? String
        let code = SyncErrorCode.from(code: codeValue, legacyMessage: message)

        AppLog.error(.sync, "sync_error_classified", data: [
            "code": code.rawValue,
            "message": AppLog.sanitizeForLog(message),
            "recipeId": UserIdFormatter.redactRecipeId(recipeId)
        ])
        onSyncError?(code, message, recipeId)
    }

    /// Web sends `recipeId: undefined` for the collection; server may omit the field or send null.
    private func collectionRecipeId(from value: Any?) -> String {
        guard let value else { return "collection" }
        if value is NSNull { return "collection" }
        if let recipeId = value as? String, !recipeId.isEmpty {
            return recipeId
        }
        return "collection"
    }
}
