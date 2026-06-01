import Foundation
import OSLog
import SocketIO

/// Handles all Socket.IO events for Y.Doc synchronization.
///
/// Parses incoming events, converts binary payloads, and delegates
/// to callbacks provided by YjsSyncService.
final class SyncEventHandler {
    private static let logger = Logger(subsystem: "com.recipescaler.native", category: "SyncEventHandler")

    // MARK: - Callbacks (set by YjsSyncService)

    /// Called when a full document state is loaded from the server.
    var onDocumentLoaded: ((String, Data, String?) -> Void)?

    /// Called when batch documents are loaded.
    var onDocumentsLoaded: ([(String, Data, String?)]) -> Void = { _ in }

    /// Called when an incremental update arrives for a recipe.
    var onRecipeUpdated: ((String, Data) -> Void)?

    /// Called when an incremental update arrives for the collection.
    var onCollectionUpdated: ((Data) -> Void)?

    /// Called on sync error.
    var onSyncError: ((String, String?) -> Void)?

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
            Self.logger.error("document_loaded: invalid payload format")
            return
        }

        // Server returns recipeId=nil for collection document (we send {} without recipeId)
        let recipeId = collectionRecipeId(from: payload["recipeId"])
        guard let stateData = YjsPayloadBytes.data(from: payload["yjsState"]) else {
            Self.logger.error("document_loaded: missing or invalid yjsState for \(recipeId)")
            return
        }
        let lastSyncedAt = payload["lastSyncedAt"] as? String

        Self.logger.info("document_loaded: \(recipeId), \(stateData.count) bytes")
        if recipeId == "collection" {
            Self.logger.info("collection document_loaded: \(stateData.count) bytes")
        }
        onDocumentLoaded?(recipeId, stateData, lastSyncedAt)
    }

    private func handleDocumentsLoaded(_ data: [Any]) {
        guard let payload = data.first as? [String: Any],
              let documents = payload["documents"] as? [[String: Any]] else {
            Self.logger.error("documents_loaded: invalid payload format")
            return
        }

        var results: [(String, Data, String?)] = []
        for doc in documents {
            let recipeId = collectionRecipeId(from: doc["recipeId"])
            guard let stateData = YjsPayloadBytes.data(from: doc["yjsState"]) else {
                Self.logger.warning("documents_loaded: skipping doc with missing yjsState for \(recipeId)")
                continue
            }
            let lastSyncedAt = doc["lastSyncedAt"] as? String
            results.append((recipeId, stateData, lastSyncedAt))
        }

        Self.logger.info("documents_loaded: \(results.count) documents")
        onDocumentsLoaded(results)
    }

    private func handleRecipeUpdated(_ data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            Self.logger.error("recipe_updated: invalid payload format")
            return
        }

        let recipeId = payload["recipeId"] as? String ?? "unknown"
        guard let updateData = YjsPayloadBytes.data(from: payload["yjsUpdate"]) else {
            Self.logger.warning("recipe_updated: missing yjsUpdate for \(recipeId)")
            return
        }

        Self.logger.debug("recipe_updated: \(recipeId), \(updateData.count) bytes")
        onRecipeUpdated?(recipeId, updateData)
    }

    private func handleCollectionUpdated(_ data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            Self.logger.error("collection_updated: invalid payload format")
            return
        }

        guard let updateData = YjsPayloadBytes.data(from: payload["yjsUpdate"]) else {
            Self.logger.warning("collection_updated: missing yjsUpdate")
            return
        }

        Self.logger.debug("collection_updated: \(updateData.count) bytes")
        onCollectionUpdated?(updateData)
    }

    private func handleSyncConfirmed(_ data: [Any]) {
        guard let payload = data.first as? [String: Any] else { return }
        let recipeId = payload["recipeId"] as? String ?? "unknown"
        let lastSyncedAt = payload["lastSyncedAt"] as? String
        Self.logger.debug("sync_confirmed: \(recipeId)")
        onSyncConfirmed?(recipeId, lastSyncedAt)
    }

    private func handleSyncError(_ data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            Self.logger.error("sync_error: invalid payload format")
            return
        }

        let message = payload["error"] as? String ?? "Unknown sync error"
        let recipeId = payload["recipeId"] as? String

        Self.logger.error("sync_error: \(message), recipeId: \(recipeId ?? "none")")
        onSyncError?(message, recipeId)
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
