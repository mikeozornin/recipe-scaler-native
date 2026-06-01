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
    @Published private(set) var writeSyncStates: [String: WriteSyncState] = [:]
    @Published var syncErrorMessage: String?
    @Published private(set) var activeRecipeWasRemoved = false

    func acknowledgeRecipeRemoved() {
        activeRecipeWasRemoved = false
    }

    private let documentManager: DocumentManager
    private let store: YDocStore
    private let offlineQueue: OfflineWriteQueue
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
    private var localUpdateHandlerInstalled = false
    private var recipeRefreshSuspended = 0
    private lazy var updateDebouncer: UpdateDebouncer = UpdateDebouncer { [weak self] recipeId, update in
        await self?.sendDebouncedUpdate(recipeId: recipeId, update: update)
    }

    init(store: YDocStore) {
        self.store = store
        self.offlineQueue = OfflineWriteQueue(store: store)
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

    func writeSyncState(for recipeId: String) -> WriteSyncState {
        writeSyncStates[recipeId] ?? .idle
    }

    func patchCurrentRecipeForEditing(ingredient: IngredientData? = nil, nutrition: NutritionData? = nil) {
        patchCurrentRecipe(ingredient: ingredient, nutrition: nutrition)
    }

    func suspendRecipeRefresh() {
        recipeRefreshSuspended += 1
    }

    func resumeRecipeRefresh() async {
        guard recipeRefreshSuspended > 0 else { return }
        recipeRefreshSuspended -= 1
        guard recipeRefreshSuspended == 0, let recipeId = activeRecipeId else { return }
        await refreshCurrentRecipe(recipeId: recipeId)
    }

    // MARK: - Recipe editing (Phase 3)

    func updateRecipeName(_ name: String) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await documentManager.updateRecipeName(recipeId: recipeId, name: trimmed)
        patchCurrentRecipe(name: trimmed)
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    func updateRecipeServings(_ servings: Int) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        try await documentManager.updateRecipeServings(recipeId: recipeId, servings: servings)
        patchCurrentRecipe(servings: servings)
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    func updateRecipeColor(_ color: String) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        let normalized = RecipeAccentColor.normalizedStored(color)
        try await documentManager.updateRecipeColor(recipeId: recipeId, color: normalized)
        patchCurrentRecipe(color: normalized)
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    func moveIngredient(fromIndex: Int, toIndex: Int) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        try await documentManager.moveIngredient(recipeId: recipeId, fromIndex: fromIndex, toIndex: toIndex)
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    func flushPendingEdits() async {
        guard let recipeId = activeRecipeId else { return }
        await updateDebouncer.flushNow(recipeId: recipeId)
    }

    func addIngredient(_ ingredient: IngredientData) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        try await documentManager.addIngredient(recipeId: recipeId, ingredient: ingredient)
        patchCurrentRecipe(ingredient: ingredient)
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    func updateIngredient(_ ingredient: IngredientData) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        try await documentManager.updateIngredient(recipeId: recipeId, ingredient: ingredient)
        patchCurrentRecipe(ingredient: ingredient)
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    func removeIngredient(id: String) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        try await documentManager.removeIngredient(recipeId: recipeId, ingredientId: id)
        if var recipe = currentRecipe, recipe.id == recipeId {
            recipe = recipe.replacing(ingredients: recipe.ingredients.filter { $0.id != id })
            currentRecipe = recipe
        }
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    func updateNutrition(
        calories: Double?,
        protein: Double?,
        fat: Double?,
        carbs: Double?
    ) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        try await documentManager.updateNutrition(
            recipeId: recipeId,
            calories: calories,
            protein: protein,
            fat: fat,
            carbs: carbs
        )
        patchCurrentRecipe(
            nutrition: NutritionData(
                calories: calories,
                protein: protein,
                fat: fat,
                carbs: carbs,
                extra: [:]
            )
        )
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
        await flushPendingEdits()
    }

    /// Start synchronization for the given user.
    /// Should be called after successful authentication.
    func start(userId: String) async {
        let isSameUser = self.userId == userId
        if !isSameUser, self.userId != nil {
            await documentManager.clearOfflineQueueForAccountSwitch()
            writeSyncStates = [:]
        }
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
            Task { await drainOfflineQueue() }
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

        eventHandler.onSyncConfirmed = { [weak self] recipeId, lastSyncedAt in
            Task { @MainActor in
                await self?.handleSyncConfirmed(recipeId: recipeId, lastSyncedAt: lastSyncedAt)
            }
        }
    }

    private func handleLocalRecipeUpdate(recipeId: String, update: Data) async {
        writeSyncStates[recipeId] = .pendingLocal
        await updateDebouncer.schedule(recipeId: recipeId, update: update)
    }

    private func sendDebouncedUpdate(recipeId: String, update: Data) async {
        guard let userId else { return }
        let docKey = docKeyFor(recipeId: recipeId)

        if socket?.status == .connected, isSocketAuthenticated {
            writeSyncStates[recipeId] = .syncing
            await emitSyncRequest(recipeId: recipeId, update: update, docKey: docKey)
        } else {
            writeSyncStates[recipeId] = .queued
            try? await offlineQueue.enqueue(docKey: docKey, recipeId: recipeId, yjsUpdate: update)
            logger.info("Queued offline update for \(recipeId) (\(update.count) bytes)")
        }
    }

    private func emitSyncRequest(recipeId: String, update: Data, docKey: String) async {
        guard socket?.status == .connected, isSocketAuthenticated else { return }
        let lastSyncedAt = try? await store.loadSnapshot(docKey: docKey)?.lastSyncedAt
        var payload: [String: Any] = [
            "recipeId": recipeId,
            "yjsUpdate": YjsPayloadBytes.array(from: update),
        ]
        if let lastSyncedAt {
            payload["lastSyncedAt"] = lastSyncedAt
        }
        socket?.emit("sync_request", payload)
        logger.info("Emitted sync_request for \(recipeId) (\(update.count) bytes)")
    }

    private func handleSyncConfirmed(recipeId: String, lastSyncedAt: String?) async {
        guard recipeId != "collection", recipeId != "unknown" else { return }
        let docKey = docKeyFor(recipeId: recipeId)
        writeSyncStates[recipeId] = .synced

        if let doc = await documentManager.getDoc(key: docKey),
           let state = await doc.encodeStateAsUpdate() {
            try? await store.saveSnapshot(docKey: docKey, state: state, lastSyncedAt: lastSyncedAt)
        }

        if let queue = try? await offlineQueue.fetchAll() {
            for entry in queue where entry.recipeId == recipeId {
                if let id = entry.id {
                    try? await offlineQueue.deleteEntry(id: id)
                }
            }
        }
    }

    private func drainOfflineQueue() async {
        guard socket?.status == .connected, isSocketAuthenticated else { return }
        guard let entries = try? await offlineQueue.fetchAll(), !entries.isEmpty else { return }

        var byDocKey: [String: [OfflineSyncEntry]] = [:]
        for entry in entries {
            byDocKey[entry.docKey, default: []].append(entry)
        }

        for (docKey, docEntries) in byDocKey {
            guard let recipeId = docEntries.first?.recipeId else { continue }
            let merged: Data
            if docEntries.count == 1 {
                merged = docEntries[0].yjsUpdate
            } else if let doc = await documentManager.getDoc(key: docKey),
                      let snapshot = await doc.encodeStateAsUpdate() {
                merged = snapshot
            } else {
                merged = docEntries.last!.yjsUpdate
            }
            writeSyncStates[recipeId] = .syncing
            await emitSyncRequest(recipeId: recipeId, update: merged, docKey: docKey)
            for entry in docEntries {
                if let id = entry.id {
                    try? await offlineQueue.deleteEntry(id: id)
                }
            }
        }
        logger.info("Drained offline sync queue (\(entries.count) entries)")
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
            await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
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

        let suppressObserver = recipeRefreshSuspended > 0 && activeRecipeId == recipeId
        do {
            try await documentManager.applyUpdate(
                key: docKey,
                data: updateData,
                suppressRecipeChangeNotification: suppressObserver
            )
        } catch {
            logger.error("Failed to apply recipe update for \(docKey): \(error)")
            requestDocumentReload(recipeId: recipeId)
            return
        }

        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
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

    // MARK: - Recipe image prefetch

    private func scheduleImagePrefetch(for entries: [CollectionEntry]) {
        let allowNetwork = connectionState == .connected
        Task {
            await RecipeImageService.shared.prefetchPreviews(
                entries: entries,
                allowNetwork: allowNetwork
            )
        }
    }

    // MARK: - Collection Reading

    private func refreshCollectionEntries() async {
        do {
            let entries = try await documentManager.readCollectionEntries()
            let filtered = entries.filter { !$0.deleted }
            collectionEntries = filtered
            syncActiveRecipeFromCollection()
            scheduleImagePrefetch(for: filtered)
            logger.info("Collection refreshed: \(filtered.count) active entries (total \(entries.count))")
        } catch {
            logger.error("Failed to read collection entries: \(error)")
        }
    }

    private func collectionEntry(for recipeId: String) -> CollectionEntry? {
        collectionEntries.first { $0.id == recipeId }
    }

    private func syncActiveRecipeFromCollection() {
        guard let recipeId = activeRecipeId,
              var recipe = currentRecipe,
              recipe.id == recipeId,
              let entry = collectionEntry(for: recipeId) else { return }
        currentRecipe = RecipeCollectionMerge.merged(recipe, with: entry)
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
        if !localUpdateHandlerInstalled {
            localUpdateHandlerInstalled = true
            await documentManager.setLocalUpdateHandler { [weak self] recipeId, update in
                await self?.handleLocalRecipeUpdate(recipeId: recipeId, update: update)
            }
        }
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
                    await self?.refreshCurrentRecipeIfAllowed(recipeId: recipeId)
                }
            }
        )
    }

    private func refreshCurrentRecipeIfAllowed(recipeId: String) async {
        guard recipeRefreshSuspended == 0 else { return }
        await refreshCurrentRecipe(recipeId: recipeId)
    }

    private func refreshCurrentRecipe(recipeId: String) async {
        guard let userId else { return }
        guard activeRecipeId == recipeId else { return }

        do {
            guard var recipe = try await documentManager.readRecipeData(recipeId: recipeId, userId: userId) else {
                currentRecipe = nil
                return
            }
            recipe = RecipeCollectionMerge.merged(recipe, with: collectionEntry(for: recipeId))
            currentRecipe = recipe
        } catch {
            logger.error("Failed to read recipe \(recipeId): \(error)")
        }
    }

    private func patchCurrentRecipe(
        name: String? = nil,
        servings: Int? = nil,
        color: String? = nil,
        ingredient: IngredientData? = nil,
        nutrition: NutritionData? = nil
    ) {
        guard let recipe = currentRecipe, recipe.id == activeRecipeId else { return }
        var ingredients = recipe.ingredients
        if let ingredient {
            if let index = ingredients.firstIndex(where: { $0.id == ingredient.id }) {
                ingredients[index] = ingredient
            } else {
                ingredients.append(ingredient)
            }
        }
        currentRecipe = recipe.replacing(
            name: name,
            servings: servings,
            color: color,
            ingredients: ingredient == nil ? nil : ingredients,
            nutrition: nutrition.map { Optional.some($0) }
        )
    }

    private func handleSyncError(message: String, recipeId: String?) async {
        logger.error("Sync error: \(message), recipeId: \(recipeId ?? "none")")

        if let recipeId, recipeId != "collection" {
            writeSyncStates[recipeId] = .error(message)
            if activeRecipeId == recipeId {
                syncErrorMessage = localizedSyncError(message)
            }
        }

        if message.contains("Ownership validation failed") {
            connectionState = .error(message)
            return
        }

        if message.contains("Recipe is deleted"), let recipeId {
            if activeRecipeId == recipeId {
                currentRecipe = nil
                activeRecipeId = nil
                activeRecipeWasRemoved = true
            }
            try? await offlineQueue.clear(forRecipeId: recipeId)
            writeSyncStates.removeValue(forKey: recipeId)
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

    private func localizedSyncError(_ message: String) -> String {
        if message.contains("Ownership validation failed") {
            return String(localized: "edit.error.ownership")
        }
        if message.contains("Recipe is deleted") {
            return String(localized: "edit.error.deleted")
        }
        if message.contains("Invalid update") || message.contains("Empty") {
            return String(localized: "edit.error.invalidUpdate")
        }
        return message
    }
}
