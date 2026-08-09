import Foundation

import SocketIO

struct CollectionSyncSummary: Equatable, Sendable {
    let liveCount: Int
    let deletedCount: Int
    let totalCount: Int
    let liveRecipeIds: Set<String>
}

struct SyncSocketSessionContext: Equatable, @unchecked Sendable {
    let sessionId: UUID
    let userId: String
    let clientIdentifier: ObjectIdentifier

    init(sessionId: UUID, userId: String, client: SocketIOClient) {
        self.init(
            sessionId: sessionId,
            userId: userId,
            clientIdentifier: ObjectIdentifier(client)
        )
    }

    init(
        sessionId: UUID,
        userId: String,
        clientIdentifier: ObjectIdentifier
    ) {
        self.sessionId = sessionId
        self.userId = userId
        self.clientIdentifier = clientIdentifier
    }

    static func == (lhs: SyncSocketSessionContext, rhs: SyncSocketSessionContext) -> Bool {
        lhs.sessionId == rhs.sessionId
            && lhs.userId == rhs.userId
            && lhs.clientIdentifier == rhs.clientIdentifier
    }

    #if DEBUG
    static let testValue: SyncSocketSessionContext = {
        let marker = SyncSocketSessionTestMarker()
        return SyncSocketSessionContext(
            sessionId: UUID(),
            userId: "test-user",
            clientIdentifier: ObjectIdentifier(marker)
        )
    }()
    #endif
}

#if DEBUG
private final class SyncSocketSessionTestMarker {}
#endif

/// Handles all Socket.IO events for Y.Doc synchronization.
///
/// Parses incoming events, converts binary payloads, and delegates
/// to callbacks provided by YjsSyncService.
final class SyncEventHandler {

    // MARK: - Callbacks (set by YjsSyncService)

    /// Called when a full document state is loaded from the server.
    var onDocumentLoaded: ((SyncSocketSessionContext, String, Data, String?) -> Void)?

    /// Called when batch documents are loaded.
    var onDocumentsLoaded: (SyncSocketSessionContext, [(String, Data, String?)]) -> Void = { _, _ in }

    /// Called when the server replies to `sync_step1` with the missing ops
    /// relative to the state vector the client sent. New primary load path;
    /// mirrors web `yjs-client.ts` `sync_step2` handler.
    ///
    var onSyncStep2WithContext: ((SyncSocketSessionContext, String, Data, String?, CollectionSyncSummary?) -> Void)?
    #if DEBUG
    /// Legacy test seam. Production wiring must use the context-bearing callback.
    var onSyncStep2: ((String, Data, String?) -> Void)?
    #endif

    /// Called when an incremental update arrives for a recipe.
    var onRecipeUpdated: ((SyncSocketSessionContext, String, Data) -> Void)?

    /// Called when an incremental update arrives for the collection.
    var onCollectionUpdated: ((SyncSocketSessionContext, Data) -> Void)?

    /// Called when an incremental update arrives for the shopping list.
    var onShoppingListUpdated: ((SyncSocketSessionContext, Data) -> Void)?

    /// Called on sync error.
    ///
    /// - Parameters in closure: `(code, message, recipeId)`
    ///   - `code`: typed `SyncErrorCode` resolved from `payload["code"]` (future)
    ///     or from the legacy English `payload["error"]` substring.
    ///   - `message`: raw `payload["error"]` string (kept for logging only —
    ///     never reaches the UI directly).
    ///   - `recipeId`: optional related recipe id.
    var onSyncError: ((SyncSocketSessionContext, SyncErrorCode, String, String?) -> Void)?

    /// Called when sync is confirmed (recipeId, lastSyncedAt).
    var onSyncConfirmed: ((SyncSocketSessionContext, String, String?) -> Void)?

    // MARK: - Event Registration

    /// Register all Socket.IO event handlers on the given client.
    ///
    /// The context is captured by every callback so an old Socket.IO client
    /// cannot be mistaken for the current session after reconnect/account switch.
    func registerHandlers(on client: SocketIOClient, context: SyncSocketSessionContext) {
        client.on("document_loaded") { [weak self] data, _ in
            self?.handleDocumentLoaded(data, context: context)
        }

        client.on("documents_loaded") { [weak self] data, _ in
            self?.handleDocumentsLoaded(data, context: context)
        }

        client.on("sync_step2") { [weak self] data, _ in
            self?.handleSyncStep2(data, context: context)
        }

        client.on("recipe_updated") { [weak self] data, _ in
            self?.handleRecipeUpdated(data, context: context)
        }

        client.on("collection_updated") { [weak self] data, _ in
            self?.handleCollectionUpdated(data, context: context)
        }

        client.on("shopping_list_updated") { [weak self] data, _ in
            self?.handleShoppingListUpdated(data, context: context)
        }

        client.on("sync_confirmed") { [weak self] data, _ in
            self?.handleSyncConfirmed(data, context: context)
        }

        client.on("sync_error") { [weak self] data, _ in
            self?.handleSyncError(data, context: context)
        }
    }

    // MARK: - Handlers

    private func handleDocumentLoaded(_ data: [Any], context: SyncSocketSessionContext) {
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
        onDocumentLoaded?(context, recipeId, stateData, lastSyncedAt)
    }

    private func handleDocumentsLoaded(_ data: [Any], context: SyncSocketSessionContext) {
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
        onDocumentsLoaded(context, results)
    }

    #if DEBUG
    /// Test seam: parse a synthetic Socket.IO `sync_step2` payload array.
    func test_handleSyncStep2(_ data: [Any], context: SyncSocketSessionContext = .testValue) {
        handleSyncStep2(data, context: context)
    }
    #endif

    /// `sync_step2` reply to our `sync_step1`. Carries the missing ops
    /// relative to the state vector we sent. Decode via `YjsPayloadBytes`
    /// so binary `Data` frames and legacy JSON number arrays both work.
    private func handleSyncStep2(_ data: [Any], context: SyncSocketSessionContext) {
        guard let payload = data.first as? [String: Any] else {
            AppLog.error(.sync, "sync_step2: invalid payload format")
            return
        }

        let documentKind = payload["documentKind"] as? String
        let recipeId: String
        if documentKind == ShoppingListConstants.documentKind {
            recipeId = ShoppingListConstants.offlineRecipeId
        } else {
            recipeId = collectionRecipeId(from: payload["recipeId"])
        }
        guard let updateData = YjsPayloadBytes.data(from: payload["missingUpdate"]) else {
            AppLog.error(.sync, "sync_step2: missing or invalid missingUpdate for \(recipeId)")
            return
        }
        let lastSyncedAt = payload["lastSyncedAt"] as? String
        let collectionSummary: CollectionSyncSummary?
        if recipeId == "collection",
           let rawSummary = payload["collectionSummary"] as? [String: Any] {
            collectionSummary = Self.parseCollectionSummary(rawSummary)
        } else {
            collectionSummary = nil
        }
        AppLog.info(.sync, "sync_step2: \(recipeId), \(updateData.count) bytes")
        if let onSyncStep2WithContext {
            onSyncStep2WithContext(context, recipeId, updateData, lastSyncedAt, collectionSummary)
        } else {
            #if DEBUG
            onSyncStep2?(recipeId, updateData, lastSyncedAt)
            #endif
        }
    }

    private func handleRecipeUpdated(_ data: [Any], context: SyncSocketSessionContext) {
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
        onRecipeUpdated?(context, recipeId, updateData)
    }

    private func handleCollectionUpdated(_ data: [Any], context: SyncSocketSessionContext) {
        guard let payload = data.first as? [String: Any] else {
            AppLog.error(.sync, "collection_updated: invalid payload format")
            return
        }

        guard let updateData = YjsPayloadBytes.data(from: payload["yjsUpdate"]) else {
            AppLog.notice(.sync, "collection_updated: missing yjsUpdate")
            return
        }

        AppLog.debug(.sync, "collection_updated: \(updateData.count) bytes")
        onCollectionUpdated?(context, updateData)
    }

    private func handleShoppingListUpdated(_ data: [Any], context: SyncSocketSessionContext) {
        guard let payload = data.first as? [String: Any] else {
            AppLog.error(.sync, "shopping_list_updated: invalid payload format")
            return
        }

        guard let updateData = YjsPayloadBytes.data(from: payload["yjsUpdate"]) else {
            AppLog.notice(.sync, "shopping_list_updated: missing yjsUpdate")
            return
        }

        AppLog.debug(.sync, "shopping_list_updated: \(updateData.count) bytes")
        onShoppingListUpdated?(context, updateData)
    }

    private func handleSyncConfirmed(_ data: [Any], context: SyncSocketSessionContext) {
        guard let payload = data.first as? [String: Any] else { return }
        let documentKind = payload["documentKind"] as? String
        let recipeId: String
        if documentKind == ShoppingListConstants.documentKind {
            recipeId = ShoppingListConstants.offlineRecipeId
        } else {
            recipeId = collectionRecipeId(from: payload["recipeId"])
        }
        let lastSyncedAt = payload["lastSyncedAt"] as? String
        AppLog.debug(.sync, "sync_confirmed: \(recipeId)")
        onSyncConfirmed?(context, recipeId, lastSyncedAt)
    }

    private func handleSyncError(_ data: [Any], context: SyncSocketSessionContext) {
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
        onSyncError?(context, code, message, recipeId)
    }

    private static func parseCollectionSummary(_ payload: [String: Any]) -> CollectionSyncSummary? {
        func integer(_ key: String) -> Int? {
            if let value = payload[key] as? Int {
                return value
            }
            if let value = payload[key] as? NSNumber {
                return value.intValue
            }
            return nil
        }

        guard let liveCount = integer("live"),
              let deletedCount = integer("deleted"),
              let totalCount = integer("total"),
              let ids = payload["liveRecipeIds"] as? [String],
              liveCount >= 0,
              deletedCount >= 0,
              totalCount == liveCount + deletedCount else {
            return nil
        }

        return CollectionSyncSummary(
            liveCount: liveCount,
            deletedCount: deletedCount,
            totalCount: totalCount,
            liveRecipeIds: Set(ids)
        )
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
