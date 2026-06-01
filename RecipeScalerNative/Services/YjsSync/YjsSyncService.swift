import Foundation
import OSLog
import SocketIO

/// Central service for Y.Doc synchronization via Socket.IO.
///
/// Replaces the old WebSocketService. Manages the full lifecycle:
/// connect → auth → load collection → receive real-time updates.
///
/// UI binds to `@Published collectionEntries` and `@Published connectionState`.
@MainActor
final class YjsSyncService: ObservableObject {
    @Published private(set) var collectionEntries: [CollectionEntry] = []
    @Published private(set) var currentRecipe: RecipeData?
    @Published private(set) var connectionState: ConnectionState = .disconnected

    private let documentManager: DocumentManager
    private let store: YDocStore
    private let eventHandler: SyncEventHandler
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private let logger = Logger(subsystem: "com.recipescaler.native", category: "YjsSyncService")

    private var userId: String?
    private let deviceId: String
    private var isSocketAuthenticated = false
    private var hasRequestedCollectionLoad = false
    private var collectionLoadTask: Task<Void, Never>?
    private var activeRecipeId: String?
    private var disconnectTimestamp: Date?
    private var changeHandlersInstalled = false

    init(store: YDocStore) {
        self.store = store
        self.documentManager = DocumentManager(store: store)
        self.eventHandler = SyncEventHandler()

        // Persistent device ID
        if let existing = UserDefaults.standard.string(forKey: "deviceId") {
            self.deviceId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "deviceId")
            self.deviceId = newId
        }

        wireEventHandler()
    }

    // MARK: - Public API

    /// Start synchronization for the given user.
    /// Should be called after successful authentication.
    func start(userId: String) async {
        let isSameUser = self.userId == userId
        self.userId = userId
        await documentManager.setUserId(userId)

        await loadLocalSnapshots()

        if isSameUser {
            if socket?.status == .connected, isSocketAuthenticated {
                loadCollectionDocument()
            } else if socket?.status != .connected {
                connectSocket()
            }
            return
        }

        logger.info("Starting YjsSync for user \(userId)")
        connectSocket()
    }

    /// Load a recipe document from local snapshot and sync with the server.
    func loadRecipe(recipeId: String) async {
        guard let userId else { return }
        activeRecipeId = recipeId
        await installChangeHandlersIfNeeded()

        let docKey = docKeyFor(recipeId: recipeId)
        _ = try? await documentManager.getOrCreateDoc(key: docKey)
        await refreshCurrentRecipe(recipeId: recipeId)

        guard socket?.status == .connected, isSocketAuthenticated else { return }
        socket?.emit("load_document", ["recipeId": recipeId])
        logger.info("Emitted load_document for recipe \(recipeId)")
    }

    /// Stop synchronization and clean up.
    func stop() {
        logger.info("Stopping YjsSync")
        socket?.disconnect()
        socket = nil
        manager = nil
        connectionState = .disconnected
        isSocketAuthenticated = false
        hasRequestedCollectionLoad = false
        collectionLoadTask?.cancel()
        collectionLoadTask = nil
        userId = nil
        activeRecipeId = nil
        currentRecipe = nil
    }

    // MARK: - Socket.IO Connection

    private func connectSocket() {
        guard let userId else { return }

        isSocketAuthenticated = false
        hasRequestedCollectionLoad = false
        collectionLoadTask?.cancel()
        collectionLoadTask = nil
        let serverURL = URL(string: Config.baseURL)!
        manager = SocketManager(socketURL: serverURL, config: [
            .log(false),
            .compress,
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWait(1000),
            .connectParams(["userId": userId, "deviceId": deviceId]),
        ])

        let client = manager!.defaultSocket
        self.socket = client

        // Socket lifecycle handlers
        client.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.logger.info("Socket.IO connected")
                self.connectionState = .connecting
                self.isSocketAuthenticated = false
                self.emitAuth()
            }
        }

        // Server auth ack after `auth` (payload includes `message`). Do not treat bare engine connect as auth.
        client.on("connected") { [weak self] data, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let payload = data.first as? [String: Any], payload["message"] != nil else {
                    return
                }
                self.collectionLoadTask?.cancel()
                self.logger.info("Socket.IO authenticated (server ack)")
                self.markAuthenticatedAndLoadCollection()
            }
        }

        client.on("auth_error") { [weak self] data, _ in
            Task { @MainActor in
                let message = data.first as? [String: Any]
                let detail = message?["message"] as? String ?? "Authentication failed"
                self?.logger.error("Socket.IO auth_error: \(detail)")
                self?.connectionState = .error(detail)
            }
        }

        client.on(clientEvent: .disconnect) { [weak self] _, _ in
            Task { @MainActor in
                self?.logger.info("Socket.IO disconnected")
                self?.isSocketAuthenticated = false
                self?.hasRequestedCollectionLoad = false
                self?.collectionLoadTask?.cancel()
                self?.collectionLoadTask = nil
                self?.disconnectTimestamp = Date()
                self?.connectionState = .disconnected
            }
        }

        client.on(clientEvent: .reconnectAttempt) { [weak self] _, _ in
            Task { @MainActor in
                self?.connectionState = .reconnecting
            }
        }

        client.on(clientEvent: .reconnect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.logger.info("Socket.IO reconnected")
                self.connectionState = .connecting
                self.isSocketAuthenticated = false
                self.hasRequestedCollectionLoad = false
                self.emitAuth()
            }
        }

        client.on("sync_error") { [weak self] data, _ in
            Task { @MainActor in
                let payload = data.first as? [String: Any]
                let message = payload?["error"] as? String ?? "Unknown sync error"
                let recipeId = payload?["recipeId"] as? String
                self?.logger.error("sync_error: \(message), recipeId: \(recipeId ?? "none")")
                if recipeId == nil || recipeId == "collection" {
                    self?.hasRequestedCollectionLoad = false
                }
            }
        }

        client.on(clientEvent: .error) { [weak self] data, _ in
            Task { @MainActor in
                let msg = data.first.map { String(describing: $0) } ?? "unknown"
                self?.logger.error("Socket.IO error: \(msg)")
                self?.connectionState = .error(msg)
            }
        }

        // Register sync protocol event handlers
        eventHandler.registerHandlers(on: client)
        client.connect()
        connectionState = .connecting
    }

    private func emitAuth() {
        guard let userId else { return }
        socket?.emit("auth", [
            "userId": userId,
            "deviceId": deviceId,
        ])
        logger.info("Emitted auth for user \(userId)")
        scheduleCollectionLoadAfterAuth()
    }

    /// Server `auth` runs async (validate/repair). Load collection after a short delay or sooner on server `connected` ack.
    private func scheduleCollectionLoadAfterAuth() {
        collectionLoadTask?.cancel()
        collectionLoadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                guard let self, self.socket?.status == .connected else { return }
                if self.isSocketAuthenticated { return }
                self.logger.warning("Socket auth ack timeout; loading collection after delay")
                self.markAuthenticatedAndLoadCollection()
            }
        }
    }

    private func markAuthenticatedAndLoadCollection() {
        isSocketAuthenticated = true
        connectionState = .connected
        if disconnectTimestamp != nil {
            reloadStaleDocumentsAfterReconnect()
        } else {
            loadCollectionDocument()
        }
    }

    private func loadCollectionDocument() {
        guard socket?.status == .connected else {
            logger.warning("Skipping load_document — socket not connected")
            return
        }
        guard isSocketAuthenticated else {
            logger.warning("Skipping load_document — socket not authenticated yet")
            return
        }
        guard !hasRequestedCollectionLoad else { return }
        hasRequestedCollectionLoad = true
        socket?.emit("load_document", [:] as [String: Any])
        logger.info("Emitted load_document for collection")
    }

    // MARK: - Event Handler Wiring

    private func wireEventHandler() {
        eventHandler.onDocumentLoaded = { [weak self] recipeId, stateData, lastSyncedAt in
            Task { @MainActor in
                await self?.handleDocumentLoaded(recipeId: recipeId, stateData: stateData, lastSyncedAt: lastSyncedAt)
            }
        }

        eventHandler.onDocumentsLoaded = { [weak self] documents in
            Task { @MainActor in
                await self?.handleDocumentsLoaded(documents: documents)
            }
        }

        eventHandler.onRecipeUpdated = { [weak self] recipeId, updateData in
            Task { @MainActor in
                await self?.handleRecipeUpdated(recipeId: recipeId, updateData: updateData)
            }
        }

        eventHandler.onCollectionUpdated = { [weak self] updateData in
            Task { @MainActor in
                await self?.handleCollectionUpdated(updateData: updateData)
            }
        }

        eventHandler.onSyncError = { [weak self] message, recipeId in
            Task { @MainActor in
                await self?.handleSyncError(message: message, recipeId: recipeId)
            }
        }

        eventHandler.onSyncConfirmed = { _ in /* Phase 2: no-op */ }
    }

    // MARK: - Event Handlers

    private func handleDocumentLoaded(recipeId: String, stateData: Data, lastSyncedAt: String?) async {
        let docKey = docKeyFor(recipeId: recipeId)
        logger.info("document_loaded: \(docKey), \(stateData.count) bytes")

        do {
            if recipeId == "collection" {
                try await documentManager.replaceDocument(
                    key: docKey,
                    state: stateData,
                    lastSyncedAt: lastSyncedAt
                )
            } else {
                try await documentManager.applyUpdate(
                    key: docKey,
                    data: stateData,
                    lastSyncedAt: lastSyncedAt
                )
            }
        } catch {
            logger.error("Failed to apply document state for \(docKey): \(error)")
        }

        if recipeId == "collection" {
            await refreshCollectionEntries()
        } else {
            await refreshCurrentRecipe(recipeId: recipeId)
        }
    }

    private func handleDocumentsLoaded(documents: [(String, Data, String?)]) async {
        var shouldRefreshCollection = false
        for (recipeId, stateData, lastSyncedAt) in documents {
            let docKey = docKeyFor(recipeId: recipeId)
            do {
                if recipeId == "collection" {
                    try await documentManager.replaceDocument(
                        key: docKey,
                        state: stateData,
                        lastSyncedAt: lastSyncedAt
                    )
                } else {
                    try await documentManager.applyUpdate(
                        key: docKey,
                        data: stateData,
                        lastSyncedAt: lastSyncedAt
                    )
                }
                if recipeId == "collection" {
                    shouldRefreshCollection = true
                }
            } catch {
                logger.error("Failed to apply batch doc \(docKey): \(error)")
            }
        }
        if shouldRefreshCollection {
            await refreshCollectionEntries()
        }
    }

    private func handleRecipeUpdated(recipeId: String, updateData: Data) async {
        let docKey = docKeyFor(recipeId: recipeId)
        logger.debug("recipe_updated: \(docKey), \(updateData.count) bytes")

        do {
            try await documentManager.applyUpdate(key: docKey, data: updateData)
        } catch {
            logger.error("Failed to apply recipe update for \(docKey): \(error)")
            requestDocumentReload(recipeId: recipeId)
            return
        }

        await refreshCurrentRecipe(recipeId: recipeId)
    }

    private func handleCollectionUpdated(updateData: Data) async {
        guard let userId else { return }
        let collectionKey = "\(userId):collection"
        logger.debug("collection_updated: \(updateData.count) bytes")

        do {
            try await documentManager.applyUpdate(key: collectionKey, data: updateData)
        } catch {
            logger.error("Failed to apply collection update: \(error)")
        }

        await refreshCollectionEntries()
    }

    // MARK: - Collection Reading

    private func refreshCollectionEntries() async {
        do {
            let entries = try await documentManager.readCollectionEntries()
            let filtered = entries.filter { !$0.deleted }
            collectionEntries = filtered
            logger.info("Collection refreshed: \(filtered.count) active entries (total \(entries.count))")
        } catch {
            logger.error("Failed to read collection entries: \(error)")
        }
    }

    // MARK: - Local Snapshot Loading

    private func loadLocalSnapshots() async {
        guard let userId else { return }
        await installChangeHandlersIfNeeded()
        let collectionKey = "\(userId):collection"

        if (try? await documentManager.getOrCreateDoc(key: collectionKey)) != nil {
            await refreshCollectionEntries()
            logger.info("Loaded collection from local snapshot")
        }
    }

    private func installChangeHandlersIfNeeded() async {
        guard !changeHandlersInstalled else { return }
        changeHandlersInstalled = true
        await documentManager.setChangeHandlers(
            onCollectionChanged: { [weak self] in
                Task { @MainActor in
                    await self?.refreshCollectionEntries()
                }
            },
            onRecipeChanged: { [weak self] recipeId in
                Task { @MainActor in
                    await self?.refreshCurrentRecipe(recipeId: recipeId)
                }
            }
        )
    }

    private func refreshCurrentRecipe(recipeId: String) async {
        guard let userId else { return }
        guard activeRecipeId == recipeId else { return }

        do {
            currentRecipe = try await documentManager.readRecipeData(recipeId: recipeId, userId: userId)
        } catch {
            logger.error("Failed to read recipe \(recipeId): \(error)")
        }
    }

    private func handleSyncError(message: String, recipeId: String?) async {
        logger.error("Sync error: \(message), recipeId: \(recipeId ?? "none")")

        if message.contains("Ownership validation failed") {
            connectionState = .error(message)
            return
        }

        if message.contains("Recipe is deleted"), let recipeId {
            if activeRecipeId == recipeId {
                currentRecipe = nil
                activeRecipeId = nil
            }
            await refreshCollectionEntries()
            return
        }

        if message.contains("Empty") || message.contains("Invalid update") {
            if let recipeId {
                requestDocumentReload(recipeId: recipeId)
            } else {
                hasRequestedCollectionLoad = false
                loadCollectionDocument()
            }
            return
        }

        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if let recipeId {
            requestDocumentReload(recipeId: recipeId)
        }
    }

    private func requestDocumentReload(recipeId: String) {
        guard socket?.status == .connected, isSocketAuthenticated else { return }
        if recipeId == "collection" {
            hasRequestedCollectionLoad = false
            loadCollectionDocument()
        } else {
            socket?.emit("load_document", ["recipeId": recipeId])
        }
    }

    private func reloadStaleDocumentsAfterReconnect() {
        guard let userId else { return }
        let collectionKey = "\(userId):collection"
        hasRequestedCollectionLoad = false
        loadCollectionDocument()

        if let recipeId = activeRecipeId {
            socket?.emit("load_document", ["recipeId": recipeId])
        }

        _ = disconnectTimestamp
        disconnectTimestamp = nil
        logger.info("Reload requested after reconnect for \(collectionKey)")
    }

    // MARK: - Persistence

    /// Persist all loaded documents to SQLite. Called on app backgrounding.
    func persistAll() async {
        await documentManager.persistAll()
    }

    // MARK: - Helpers

    private func docKeyFor(recipeId: String) -> String {
        guard let userId else { return recipeId }
        if recipeId == "collection" {
            return "\(userId):collection"
        }
        return "\(userId):recipe:\(recipeId)"
    }
}
