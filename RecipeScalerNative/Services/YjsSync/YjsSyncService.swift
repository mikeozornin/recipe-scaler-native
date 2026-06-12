import Foundation
import Network
import OSLog
import SocketIO
import RecipeScalerCore

/// Central service for Y.Doc synchronization via Socket.IO.
///
/// Replaces the old WebSocketService. Manages the full lifecycle:
/// connect → auth → load collection → receive real-time updates.
///
/// UI binds to `@Published collectionEntries` and `@Published connectionState`.
@MainActor
final class YjsSyncService: ObservableObject {
    @Published private(set) var collectionEntries: [CollectionEntry] = []
    /// Active (non-deleted) folders from the collection doc, sorted for display.
    @Published private(set) var folders: [RecipeFolder] = []
    /// Derived in-memory index for the collections view.
    @Published private(set) var collectionIndex: CollectionRecipesIndex = CollectionRecipesIndex(
        live: [], uncategorized: [], countByFolder: [:], folderRecipesById: [:]
    )
    @Published private(set) var shoppingSnapshot: ShoppingListSnapshot = .empty
    @Published private(set) var currentRecipe: RecipeData?
    /// Whether the initial local snapshot load has completed. Used by collection views
    /// to avoid rendering empty state during cold start.
    @Published private(set) var isLocalDataLoaded = false
    @Published private(set) var connectionState: ConnectionState = .disconnected
    /// Polling-first matches PWA `websocket-service` and avoids Starscream direct-WSS hangs on iOS.
    @Published private(set) var connectionTransport: SyncConnectionTransport = .pollingAndWebsocket
    @Published private(set) var writeSyncStates: [String: WriteSyncState] = [:]
    @Published var syncErrorMessage: String?
    @Published private(set) var activeRecipeWasRemoved = false
    @Published private(set) var imageCacheStatus = RecipeImageCacheStatus()
    @Published private(set) var recipeDocumentCacheStatus = RecipeDocumentCacheStatus()
    @Published private(set) var lastSuccessfulSyncAt: Date?

    func acknowledgeRecipeRemoved() {
        activeRecipeWasRemoved = false
    }

    private let documentManager: DocumentManager
    private let store: YDocStore
    private let offlineQueue: OfflineWriteQueue
    private let eventHandler: SyncEventHandler
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    /// Guards socket handlers: stale clients must not overwrite `connectionState` after reconnect.
    private var socketSessionId = UUID()
    private let logger = Logger(subsystem: "com.recipescaler.native", category: "YjsSyncService")

    private var userId: String?
    private let deviceId: String
    private var isSocketAuthenticated = false
    private var hasRequestedCollectionLoad = false
    private var hasRequestedShoppingLoad = false
    private var collectionLoadTask: Task<Void, Never>?
    private var recipeBatchLoadTask: Task<Void, Never>?
    private var recipeBatchLoadInFlight = false
    private var recipeBatchLoadCompleted = 0
    private var recipeBatchLoadTotal = 0

    private var connectingWatchdogTask: Task<Void, Never>?
    private var engineConnectTimeoutTask: Task<Void, Never>?
    private var activeRecipeId: String?
    private var disconnectTimestamp: Date?
    private var changeHandlersInstalled = false
    private var localUpdateHandlerInstalled = false
    private var recipeRefreshSuspended = 0
    private lazy var updateDebouncer: UpdateDebouncer = UpdateDebouncer { [weak self] recipeId, update in
        await self?.sendDebouncedUpdate(recipeId: recipeId, update: update)
    }
    private var imageCacheStatusRefreshTask: Task<Void, Never>?
    private var imageCacheObserversInstalled = false
    private var descriptionEditorSessions: [String: DescriptionEditorSession] = [:]
    private var networkPathMonitor: NWPathMonitor?
    private var isNetworkReachable = true

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

    /// After REST image upload — patch local Y.Doc immediately (web `saveRecipeWithScaleFactor` parity).
    func applyRecipeImageUpload(recipeId: String, result: RecipeImageUploadResult) async throws {
        try await documentManager.updateRecipeImage(
            recipeId: recipeId,
            imageUrl: result.imageUrl,
            aspectRatio: result.aspectRatio
        )
        await refreshCurrentRecipe(recipeId: recipeId)
        await refreshCollectionEntries()
        await RecipeImageService.shared.removeCache(recipeId: recipeId)
        if connectionState == .connected {
            await RecipeImageService.shared.prefetchFull(
                recipeId: recipeId,
                imageUrl: result.imageUrl,
                allowNetwork: true
            )
        }
    }

    func applyRecipeImageDeletion(recipeId: String) async throws {
        try await documentManager.clearRecipeImage(recipeId: recipeId)
        await RecipeImageService.shared.removeCache(recipeId: recipeId)
        await refreshCurrentRecipe(recipeId: recipeId)
        await refreshCollectionEntries()
    }

    func moveIngredient(fromIndex: Int, toIndex: Int) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        try await documentManager.moveIngredient(recipeId: recipeId, fromIndex: fromIndex, toIndex: toIndex)
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    func flushPendingEdits() async {
        guard let recipeId = activeRecipeId else { return }
        // Flush the open description editor's debounced reconcile first, so its last
        // edits are posted + applied to the doc before we drain the outbound queue.
        if let bridge = descriptionEditorSessions[recipeId]?.bridge {
            await bridge.flushEditorEdits()
        }
        await flushPendingUpdates(for: pendingEditRecipeIds())
    }

    private func pendingEditRecipeIds() -> [String] {
        var ids: [String] = []
        if let recipeId = activeRecipeId {
            ids.append(recipeId)
        }
        ids.append("collection")
        return ids
    }

    private func flushPendingUpdates(for recipeIds: [String]) async {
        for recipeId in recipeIds {
            guard let batch = await updateDebouncer.drainPendingBatch(recipeId: recipeId) else {
                continue
            }
            for payload in batch where payload.count > 2 {
                await sendDebouncedUpdate(recipeId: recipeId, update: payload)
            }
        }
        for recipeId in recipeIds {
            await documentManager.persistSnapshot(docKey: docKeyFor(recipeId: recipeId))
        }
    }

    private func canSendLiveSync() -> Bool {
        isNetworkReachable
            && connectionState.isConnected
            && socket?.status == .connected
            && isSocketAuthenticated
    }

    /// Offline-first: local SQLite + in-memory Y.Doc may have edits not yet acknowledged by the server.
    private func hasUnsyncedLocalChanges(recipeId: String) async -> Bool {
        switch writeSyncStates[recipeId] ?? .idle {
        case .queued, .syncing, .pendingLocal:
            return true
        case .idle, .synced, .error:
            break
        }
        if let entries = try? await offlineQueue.fetchAll() {
            return entries.contains { $0.recipeId == recipeId }
        }
        return false
    }

    private func startNetworkMonitorIfNeeded() {
        guard networkPathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let reachable = path.status == .satisfied
                if self.isNetworkReachable != reachable {
                    self.isNetworkReachable = reachable
                    if !reachable {
                        self.reconcileStuckSyncingStates()
                        Task { await self.flushPendingUpdates(for: self.pendingEditRecipeIds()) }
                    }
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.recipescaler.native.network-reachability"))
        networkPathMonitor = monitor
    }

    private func stopNetworkMonitor() {
        networkPathMonitor?.cancel()
        networkPathMonitor = nil
        isNetworkReachable = true
    }

    private func reconcileStuckSyncingStates() {
        guard !isNetworkReachable || !connectionState.isConnected else { return }
        for (recipeId, state) in writeSyncStates where state == .syncing {
            writeSyncStates[recipeId] = .queued
        }
    }

    // MARK: - Description editor (006)

    struct DescriptionEditorBootstrap: Sendable {
        let state: Data
    }

    func descriptionEditorBootstrap(recipeId: String) async throws -> DescriptionEditorBootstrap {
        guard activeRecipeId == recipeId else { throw RecipeEditError.documentNotLoaded }
        let state = try await documentManager.recipeDocumentState(recipeId: recipeId)
        return DescriptionEditorBootstrap(state: state)
    }

    func applyDescriptionEditorUpdate(recipeId: String, update: Data) async throws {
        guard activeRecipeId == recipeId else { throw RecipeEditError.documentNotLoaded }
        try await documentManager.applyDescriptionEditorUpdate(recipeId: recipeId, update: update)
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    func registerDescriptionEditor(_ bridge: DescriptionEditorBridge) {
        let session = DescriptionEditorSession()
        session.bridge = bridge
        descriptionEditorSessions[bridge.recipeId] = session
    }

    func unregisterDescriptionEditor(recipeId: String) {
        descriptionEditorSessions.removeValue(forKey: recipeId)
    }

    func addIngredient(_ ingredient: IngredientData) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        try await documentManager.addIngredient(recipeId: recipeId, ingredient: ingredient)
        patchCurrentRecipe(ingredient: ingredient)
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    func updateIngredient(_ ingredient: IngredientData, markNutritionOutdated: Bool = true) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        try await documentManager.updateIngredient(
            recipeId: recipeId,
            ingredient: ingredient,
            markNutritionOutdated: markNutritionOutdated
        )
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

    func updateRecipeIsPublic(_ isPublic: Bool) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        try await documentManager.updateRecipeIsPublic(recipeId: recipeId, isPublic: isPublic)
        patchCurrentRecipe(isPublic: isPublic)
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    // MARK: - Collection mutations (008)

    func setRecipePinned(recipeId: String, isPinned: Bool) async throws {
        try await documentManager.setCollectionEntryPinned(recipeId: recipeId, isPinned: isPinned)
        await refreshCollectionEntries()
    }

    func deleteRecipeFromCollection(recipeId: String) async throws {
        try await documentManager.tombstoneCollectionEntry(recipeId: recipeId)
        if activeRecipeId == recipeId {
            currentRecipe = nil
            activeRecipeId = nil
            activeRecipeWasRemoved = true
        }
        writeSyncStates.removeValue(forKey: recipeId)
        await refreshCollectionEntries()
    }

    /// Creates an empty v3 recipe + collection entry; returns new recipe id.
    func createRecipe() async throws -> String {
        let name = String(localized: "recipe.create.new")
        let recipeId = try await documentManager.createRecipe(name: name)
        await refreshCollectionEntries()
        return recipeId
    }

    // MARK: - Collection folders (026)

    /// Create a new user collection. Returns the new folder id.
    @discardableResult
    func createFolder(name: String, color: String? = nil) async throws -> String {
        let id = try await documentManager.createFolder(name: name, color: color)
        await refreshFolders()
        return id
    }

    /// Rename an existing folder (active or tombstoned).
    func renameFolder(id: String, name: String) async throws {
        try await documentManager.renameFolder(id: id, name: name)
        await refreshFolders()
    }

    /// Update an existing folder accent color.
    func updateFolderColor(id: String, color: String) async throws {
        try await documentManager.updateFolderColor(id: id, color: color)
        await refreshFolders()
    }

    /// Soft-delete a folder and strip its id from every recipe's `folderIds`.
    /// Recipes are not deleted — only their membership in this collection.
    func deleteFolder(id: String) async throws {
        try await documentManager.deleteFolder(id: id)
        await refreshFolders()
        await refreshCollectionEntries()
    }

    /// Replace the set of collections a recipe belongs to.
    /// Validates ids against active folders; writes the full set in one transaction.
    func setRecipeFolders(recipeId: String, folderIds: [String]) async throws {
        try await documentManager.setRecipeFolders(recipeId: recipeId, folderIds: folderIds)
        await refreshCollectionEntries()
    }

    // MARK: - Shopping list

    func setShoppingSortMode(_ mode: ShoppingSortMode) async throws {
        try await documentManager.setShoppingSortMode(mode)
        await refreshShoppingSnapshot()
    }

    func setShoppingItemPurchased(id: String, purchased: Bool) async throws {
        try await documentManager.setShoppingItemPurchased(id: id, purchased: purchased)
        await refreshShoppingSnapshot()
    }

    func addManualShoppingItem(label: String) async throws {
        try await documentManager.addManualShoppingItem(label: label)
        await refreshShoppingSnapshot()
    }

    func addShoppingItem(_ item: ShoppingListItem) async throws {
        try await documentManager.addShoppingItems([item])
        await refreshShoppingSnapshot()
    }

    func removeShoppingItem(id: String) async throws {
        try await documentManager.removeShoppingItem(id: id)
        await refreshShoppingSnapshot()
    }

    func updateShoppingItemLabel(id: String, label: String) async throws {
        try await documentManager.updateShoppingItemLabel(id: id, label: label)
        await refreshShoppingSnapshot()
    }

    func clearPurchasedShoppingItems() async throws {
        try await documentManager.clearPurchasedShoppingItems()
        await refreshShoppingSnapshot()
    }

    func addRecipeToShoppingList(
        recipeId: String,
        recipeName: String,
        ingredients: [IngredientData],
        selectedIngredientIds: Set<String>? = nil
    ) async throws {
        let items = ShoppingListFromRecipe.makeItems(
            recipeId: recipeId,
            recipeName: recipeName,
            ingredients: ingredients,
            ingredientIds: selectedIngredientIds
        )
        guard !items.isEmpty else { return }
        try await documentManager.addShoppingItems(items)
        await refreshShoppingSnapshot()
    }

    /// Loads recipe Y.Doc from local snapshot, then adds all eligible ingredients (recipe list swipe / menu parity).
    func addWholeRecipeToShoppingList(recipeId: String) async throws -> Int {
        guard let userId else { throw RecipeEditError.documentNotLoaded }
        _ = try? await documentManager.getOrCreateDoc(key: docKeyFor(recipeId: recipeId))
        guard let recipe = try await documentManager.readRecipeData(recipeId: recipeId, userId: userId) else {
            throw RecipeEditError.documentNotLoaded
        }
        let items = ShoppingListFromRecipe.makeItems(
            recipeId: recipeId,
            recipeName: recipe.name,
            ingredients: recipe.ingredients,
            ingredientIds: nil
        )
        guard !items.isEmpty else { return 0 }
        try await documentManager.addShoppingItems(items)
        await refreshShoppingSnapshot()
        return items.count
    }

    func updateNutrition(
        calories: Double?,
        protein: Double?,
        fat: Double?,
        carbs: Double?
    ) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        let currentOutdated = currentRecipe?.nutrition?.nutritionOutdated ?? false
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
                nutritionOutdated: currentOutdated,
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
        startNetworkMonitorIfNeeded()
        await documentManager.setUserId(userId)
        APIClient.shared.configure(userId: userId)
        TimerSyncService.shared.configure(
            userId: userId,
            deviceId: deviceId,
            timerManager: TimerManager.shared
        )
        TimerSyncService.shared.sendTimerEvent = { [weak self] type, timerId, payload in
            await self?.emitTimerEvent(type: type, timerId: timerId, eventData: payload) ?? false
        }
        installImageCacheObserversIfNeeded()

        // Connect before SQLite snapshot IO so UI is not stuck on "Offline" while docs load.
        beginSocketSession(isSameUser: isSameUser, userId: userId)


        await loadLocalSnapshots()

    }

    private func beginSocketSession(isSameUser: Bool, userId: String) {
        if isSameUser {
            // Same account: reconcile against the existing socket instead of tearing it down.
            // `start()` is re-entered whenever the root view churns; an unconditional connectSocket()
            // here drops a live, authenticated socket every time. resumeSocketSession() is idempotent:
            // it no-ops when already connected/connecting and only reconnects when the socket is down.
            resumeSocketSession()
            return
        }

        logger.info("Starting YjsSync for user \(userId)")
        connectSocket()
    }

    /// Reconcile socket after `start` is called again for the same account (view re-appear, etc.).
    private func resumeSocketSession() {
        guard let socket else {
            connectSocket()
            return
        }
        switch socket.status {
        case .connected:
            if isSocketAuthenticated {
                loadCollectionDocument()
            } else {
                emitAuth()
            }
        case .connecting:
            break
        case .notConnected, .disconnected:
            connectSocket()
        }
    }

    /// Load a recipe document from local snapshot and sync with the server.
    func loadRecipe(recipeId: String) async {
        guard userId != nil else { return }
        activeRecipeId = recipeId
        await installChangeHandlersIfNeeded()

        let docKey = docKeyFor(recipeId: recipeId)
        _ = try? await documentManager.getOrCreateDoc(key: docKey)
        await refreshCurrentRecipe(recipeId: recipeId)


        guard socket?.status == .connected, isSocketAuthenticated else { return }

        // Offline-first (web parity): local snapshot is shown immediately above; only pull
        // server state when there is nothing waiting to be pushed outward.
        if await hasUnsyncedLocalChanges(recipeId: recipeId) {
            await flushPendingUpdates(for: [recipeId])
            if canSendLiveSync() {
                await drainOfflineQueue()
            }
            if await hasUnsyncedLocalChanges(recipeId: recipeId) {
                logger.info("Skipping load_document for \(recipeId) — unsynced local changes")
                return
            }
        }

        socket?.emit("load_document", ["recipeId": recipeId])
        logger.info("Emitted load_document for recipe \(recipeId)")
    }

    /// Full local teardown on logout (web: IndexedDB + realtime destroy).
    func clearSessionForLogout() async {
        stop()
        collectionEntries = []
        folders = []
        collectionIndex = CollectionRecipesIndex(
            live: [], uncategorized: [], countByFolder: [:], folderRecipesById: [:]
        )
        writeSyncStates = [:]
        imageCacheStatus = RecipeImageCacheStatus()
        await documentManager.resetSession()
        try? await store.deleteAll()
        try? await store.deleteAllOfflineQueue()
    }

    /// Read-only access to a recipe snapshot without activating it as the current
    /// editing session. Used by Spotlight indexer to pull `description` and
    /// ingredient names for indexing. Returns nil if the snapshot is not yet
    /// synced locally — the caller may retry on the next reindex tick.
    func peekRecipeData(recipeId: String) async -> RecipeData? {
        guard let userId else { return nil }
        _ = try? await documentManager.getOrCreateDoc(key: docKeyFor(recipeId: recipeId))
        return try? await documentManager.readRecipeData(recipeId: recipeId, userId: userId)
    }

    /// The current user id, exposed read-only for indexing layers (Spotlight, etc.).
    var currentUserId: String? { userId }

    var currentDeviceId: String { deviceId }

    /// Stop synchronization and clean up.
    func stop() {
        logger.info("Stopping YjsSync")
        teardownSocket()
        stopNetworkMonitor()
        setConnectionState(.disconnected, reason: "stop")
        connectionTransport = .pollingAndWebsocket
        isLocalDataLoaded = false
        userId = nil
        activeRecipeId = nil
        currentRecipe = nil
        shoppingSnapshot = .empty
    }

    // MARK: - App lifecycle

    /// App moved to background. iOS suspends the process with the socket still open, so in-flight
    /// long-poll / websocket requests stall and resurface as a burst of "request timed out" on resume.
    /// Drop the socket cleanly instead; pending writes fall back to the offline queue.
    func handleEnteredBackground() {
        guard userId != nil else { return }
        guard connectionState != .disconnected else { return }
        logger.info("Entered background — disconnecting socket")
        teardownSocket()
        setConnectionState(.disconnected, reason: "app_background")
    }

    /// App returned to foreground. Re-establish proactively instead of waiting for the slow,
    /// timeout-driven Socket.IO auto-reconnect (a fresh connect completes in ~0.5s).
    func handleEnteredForeground() {
        guard userId != nil else { return }
        guard !canSendLiveSync() else { return }
        logger.info("Entered foreground — reconnecting socket")
        resumeSocketSession()
    }

    // MARK: - Socket.IO Connection

    private func teardownSocket() {
        collectionLoadTask?.cancel()
        collectionLoadTask = nil
        connectingWatchdogTask?.cancel()
        connectingWatchdogTask = nil
        engineConnectTimeoutTask?.cancel()
        engineConnectTimeoutTask = nil
        socket?.disconnect()
        socket = nil
        manager = nil
        isSocketAuthenticated = false
        hasRequestedCollectionLoad = false
        hasRequestedShoppingLoad = false
    }

    private func connectSocket() {
        guard let userId else { return }

        let sessionId = UUID()
        socketSessionId = sessionId

        teardownSocket()

        isSocketAuthenticated = false
        hasRequestedCollectionLoad = false
        hasRequestedShoppingLoad = false
        collectionLoadTask?.cancel()
        collectionLoadTask = nil
        let serverURL = URL(string: Config.baseURL)!
        var socketConfig: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWait(1000),
            .reconnectWaitMax(5000),
            .connectParams(["userId": userId, "deviceId": deviceId]),
        ]
        if connectionTransport == .websocketOnly {
            socketConfig.insert(.forceWebsockets(true))
        }
        manager = SocketManager(socketURL: serverURL, config: socketConfig)

        let client = manager!.defaultSocket
        self.socket = client

        // Socket lifecycle handlers
        client.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                self.logger.info("Socket.IO connected")
                self.setConnectionState(.connecting, reason: "socket.connect")
                self.isSocketAuthenticated = false
                self.scheduleCollectionLoadAfterAuth()
                self.scheduleConnectingWatchdog(sessionId: sessionId)
                self.emitAuth()
            }
        }

        // Server auth ack after `auth` (payload includes `message`). Do not treat bare engine connect as auth.
        client.on("connected") { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                guard let payload = data.first as? [String: Any], payload["message"] != nil else {
                    return
                }
                self.collectionLoadTask?.cancel()
                self.logger.info("Socket.IO authenticated (server ack)")
                self.markAuthenticatedAndLoadCollection()
            }
        }

        client.on("timer_event") { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                guard let payload = data.first as? [String: Any] else { return }
                TimerSyncService.shared.handleWebSocketPayload(payload)
            }
        }

        client.on("auth_error") { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                let message = data.first as? [String: Any]
                let detail = message?["message"] as? String ?? "Authentication failed"
                self.logger.error("Socket.IO auth_error: \(detail)")
                self.setConnectionState(.error(detail), reason: "auth_error")
            }
        }

        client.on(clientEvent: .disconnect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isCurrentSocketSession(sessionId) else {
                    return
                }
                self.logger.info("Socket.IO disconnected")
                self.isSocketAuthenticated = false
                self.hasRequestedCollectionLoad = false
                self.hasRequestedShoppingLoad = false
                self.collectionLoadTask?.cancel()
                self.collectionLoadTask = nil
                self.disconnectTimestamp = Date()
                self.recipeBatchLoadTask?.cancel()
                self.recipeBatchLoadTask = nil
                self.recipeBatchLoadInFlight = false
                self.recipeBatchLoadCompleted = 0
                self.recipeBatchLoadTotal = 0
                Task { await self.flushPendingUpdates(for: self.pendingEditRecipeIds()) }
                // Auto-reconnect is enabled — show reconnecting, not "Offline".
                self.setConnectionState(.reconnecting, reason: "socket.disconnect")
            }
        }

        client.on(clientEvent: .reconnectAttempt) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                self.isSocketAuthenticated = false
                self.hasRequestedCollectionLoad = false
                self.hasRequestedShoppingLoad = false
                self.setConnectionState(.reconnecting, reason: "reconnect_attempt")
            }
        }

        // Auth is emitted from `.connect` only — `reconnect` fires before the engine is ready.
        client.on(clientEvent: .reconnect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                self.logger.info("Socket.IO reconnected (awaiting connect for auth)")
                self.setConnectionState(.connecting, reason: "socket.reconnect")
                self.isSocketAuthenticated = false
                self.hasRequestedCollectionLoad = false
                self.hasRequestedShoppingLoad = false
            }
        }

        client.on("sync_error") { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                let payload = data.first as? [String: Any]
                let message = payload?["error"] as? String ?? "Unknown sync error"
                let recipeId = payload?["recipeId"] as? String
                self.logger.error("sync_error: \(message), recipeId: \(recipeId ?? "none")")
                if recipeId == nil || recipeId == "collection" {
                    self.hasRequestedCollectionLoad = false
                }
            }
        }

        client.on(clientEvent: .error) { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                let msg = data.first.map { String(describing: $0) } ?? "unknown"
                self.logger.error("Socket.IO error: \(msg)")
                // Engine/transport errors are always transient here: infinite auto-reconnect retries
                // them, and genuine fatal failures (auth) arrive via the dedicated `auth_error` event.
                // The payload is a localized NSError description (e.g. "Сетевое соединение потеряно."),
                // so matching against fixed English fragments misclassified them as fatal on non-English
                // devices and surfaced a stuck "Offline" instead of a silent reconnect.
                self.isSocketAuthenticated = false
                self.setConnectionState(.reconnecting, reason: "socket.error")
            }
        }

        // Register sync protocol event handlers
        eventHandler.registerHandlers(on: client)
        client.connect()
        setConnectionState(.connecting, reason: "connect_socket_called")
        scheduleCollectionLoadAfterAuth()
        scheduleEngineConnectTimeout(sessionId: sessionId)
        scheduleConnectingWatchdog(sessionId: sessionId)
    }

    private func isCurrentSocketSession(_ sessionId: UUID) -> Bool {
        socketSessionId == sessionId
    }

    private func setConnectionState(_ state: ConnectionState, reason: String) {
        connectionState = state
        if !state.isConnected {
            reconcileStuckSyncingStates()
        }
        _ = reason
    }

    private func emitAuth() {
        guard let userId else { return }
        let sessionAtEmit = socketSessionId

        if performAuthEmit(userId: userId) {
            return
        }

        // `.connect` can fire before `status == .connected` — retry briefly (was causing infinite "Connecting…").
        Task { @MainActor [weak self] in
            for attempt in 1...15 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, self.isCurrentSocketSession(sessionAtEmit) else { return }
                if self.performAuthEmit(userId: userId) {
                    return
                }
            }
        }
    }

    @discardableResult
    private func performAuthEmit(userId: String) -> Bool {
        guard let socket, socket.status == .connected else { return false }
        socket.emit("auth", [
            "userId": userId,
            "deviceId": deviceId,
        ])
        logger.info("Emitted auth for user \(userId)")
        return true
    }

    /// Engine never reaches `.connected` (WS handshake stuck on some networks).
    private func scheduleEngineConnectTimeout(sessionId: UUID) {
        engineConnectTimeoutTask?.cancel()
        engineConnectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await MainActor.run {
                self?.handleStuckEngineConnect(sessionId: sessionId, trigger: "engine_connect_timeout")
            }
        }
    }

    /// Auth emit/ack never completes after engine is up.
    private func scheduleConnectingWatchdog(sessionId: UUID) {
        connectingWatchdogTask?.cancel()
        connectingWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            await MainActor.run {
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                guard !self.isSocketAuthenticated else { return }
                switch self.connectionState {
                case .connecting, .reconnecting:
                    break
                default:
                    return
                }
                if self.socket?.status == .connected {
                    self.logger.warning("Connecting watchdog — auth retry")
                    self.scheduleCollectionLoadAfterAuth()
                    self.emitAuth()
                } else {
                    self.handleStuckEngineConnect(sessionId: sessionId, trigger: "connecting_watchdog")
                }
            }
        }
    }

    private func handleStuckEngineConnect(sessionId: UUID, trigger: String) {
        guard isCurrentSocketSession(sessionId) else { return }
        guard !isSocketAuthenticated else { return }
        guard socket?.status != .connected else {
            scheduleCollectionLoadAfterAuth()
            emitAuth()
            return
        }


        if connectionTransport == .websocketOnly {
            logger.warning("Engine connect timeout — falling back to polling+websocket")
            connectionTransport = .pollingAndWebsocket
            connectSocket()
            return
        }

        logger.warning("Engine connect still stuck after polling fallback — reconnecting")
        setConnectionState(.reconnecting, reason: trigger)
        socket?.disconnect()
    }

    /// Server `auth` runs async (validate/repair). Load collection after a short delay or sooner on server `connected` ack.
    private func scheduleCollectionLoadAfterAuth() {
        collectionLoadTask?.cancel()
        collectionLoadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                guard let self else { return }
                if self.isSocketAuthenticated { return }
                guard self.socket?.status == .connected else { return }
                self.logger.warning("Socket auth ack timeout; loading collection after delay")
                self.markAuthenticatedAndLoadCollection()
            }
        }
    }

    private func markAuthenticatedAndLoadCollection() {
        connectingWatchdogTask?.cancel()
        connectingWatchdogTask = nil
        engineConnectTimeoutTask?.cancel()
        engineConnectTimeoutTask = nil
        isSocketAuthenticated = true
        setConnectionState(.connected, reason: "authenticated")
        if disconnectTimestamp != nil {
            Task {
                await drainOfflineQueue()
                reloadStaleDocumentsAfterReconnect()
            }
        } else {
            loadCollectionDocument()
        }
        TimerSyncService.shared.initializeAfterAuth()
        Task { await PushRegistrationService.shared.registerIfNeeded() }
    }

    /// Sends a timer sync event over Socket.IO (ack); used by `TimerSyncService`.
    func emitTimerEvent(
        type: SyncedTimerEventType,
        timerId: String,
        eventData: [String: Any]
    ) async -> Bool {
        guard let socket, socket.status == .connected, isSocketAuthenticated else { return false }
        let payload: [String: Any] = [
            "eventType": type.rawValue,
            "timerId": timerId,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "eventData": eventData,
        ]
        return await withCheckedContinuation { continuation in
            socket.emitWithAck("timer_event", payload).timingOut(after: 5) { data in
                let ok: Bool
                if let first = data.first as? [String: Any],
                   let success = first["success"] as? Bool {
                    ok = success
                } else {
                    ok = !data.isEmpty
                }
                continuation.resume(returning: ok)
            }
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
        loadShoppingDocument()
    }

    private func loadShoppingDocument() {
        guard socket?.status == .connected, isSocketAuthenticated else { return }
        guard !hasRequestedShoppingLoad else { return }
        hasRequestedShoppingLoad = true
        socket?.emit("load_document", ["documentKind": ShoppingListConstants.documentKind])
        logger.info("Emitted load_document for shopping list")
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

        eventHandler.onShoppingListUpdated = { [weak self] updateData in
            Task { @MainActor in
                await self?.handleShoppingListUpdated(updateData: updateData)
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

        if canSendLiveSync() {
            writeSyncStates[recipeId] = .syncing
            await emitSyncRequest(recipeId: recipeId, update: update, docKey: docKey)
            // Web parity: persist local state on every outbound attempt, not only on sync_confirmed.
            await documentManager.persistSnapshot(docKey: docKey)
        } else {
            writeSyncStates[recipeId] = .queued
            try? await offlineQueue.enqueue(docKey: docKey, recipeId: recipeId, yjsUpdate: update)
            await documentManager.persistSnapshot(docKey: docKey)
            logger.info("Queued offline update for \(recipeId) (\(update.count) bytes)")
        }
    }

    private func handleLocalShoppingUpdate(update: Data) async {
        guard let userId else { return }
        let docKey = Self.shoppingDocKey(userId: userId)
        if socket?.status == .connected, isSocketAuthenticated {
            await emitSyncRequest(
                recipeId: ShoppingListConstants.offlineRecipeId,
                update: update,
                docKey: docKey,
                documentKind: ShoppingListConstants.documentKind
            )
        } else {
            try? await offlineQueue.enqueue(
                docKey: docKey,
                recipeId: ShoppingListConstants.offlineRecipeId,
                yjsUpdate: update
            )
            logger.info("Queued offline shopping update (\(update.count) bytes)")
        }
    }

    private func emitSyncRequest(
        recipeId: String,
        update: Data,
        docKey: String,
        documentKind: String? = nil
    ) async {
        guard socket?.status == .connected, isSocketAuthenticated else { return }
        let lastSyncedAt = try? await store.loadSnapshot(docKey: docKey)?.lastSyncedAt
        var payload: [String: Any] = [
            "yjsUpdate": YjsPayloadBytes.array(from: update),
        ]
        // Collection and shopping list sync match web: omit `recipeId` (server rejects it for shopping).
        let isShoppingList = documentKind == ShoppingListConstants.documentKind
        if recipeId != "collection", !isShoppingList {
            payload["recipeId"] = recipeId
        }
        if let documentKind {
            payload["documentKind"] = documentKind
        }
        if let lastSyncedAt {
            payload["lastSyncedAt"] = lastSyncedAt
        }
        socket?.emit("sync_request", payload)
        let target: String
        if documentKind == ShoppingListConstants.documentKind {
            target = "shoppingList"
        } else {
            target = recipeId == "collection" ? "collection" : recipeId
        }
        logger.info("Emitted sync_request for \(target) (\(update.count) bytes)")
    }

    private func handleSyncConfirmed(recipeId: String, lastSyncedAt: String?) async {
        guard recipeId != "unknown" else { return }
        lastSuccessfulSyncAt = Date()
        let docKey = docKeyFor(recipeId: recipeId)
        if recipeId != "collection", recipeId != ShoppingListConstants.offlineRecipeId {
            writeSyncStates[recipeId] = .synced
        }

        if let doc = await documentManager.getDoc(key: docKey),
           let state = await doc.encodeStateAsUpdate() {
            try? await store.saveSnapshot(docKey: docKey, state: state, lastSyncedAt: lastSyncedAt)
        }

        guard recipeId != "collection", recipeId != ShoppingListConstants.offlineRecipeId else { return }
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
            let documentKind = recipeId == ShoppingListConstants.offlineRecipeId
                ? ShoppingListConstants.documentKind
                : nil
            if recipeId != ShoppingListConstants.offlineRecipeId {
                writeSyncStates[recipeId] = .syncing
            }
            await emitSyncRequest(
                recipeId: recipeId,
                update: merged,
                docKey: docKey,
                documentKind: documentKind
            )
            for entry in docEntries {
                if let id = entry.id {
                    try? await offlineQueue.deleteEntry(id: id)
                }
            }
        }
        logger.info("Drained offline sync queue (\(entries.count) entries)")
    }

    // MARK: - Event Handlers

    /// Web parity: merge server snapshot into local doc when local state exists; replace only when empty.
    private func applyServerDocumentState(
        recipeId: String,
        docKey: String,
        stateData: Data,
        lastSyncedAt: String?
    ) async throws {
        // Offline-first: never let a server snapshot clobber edits still queued locally.
        if recipeId != "collection",
           recipeId != ShoppingListConstants.offlineRecipeId,
           await hasUnsyncedLocalChanges(recipeId: recipeId) {
            logger.info("Skipping server document for \(docKey) — unsynced local changes")
            return
        }

        let serverLooksEmpty = stateData.count <= 2
        var localState: Data?
        if let doc = await documentManager.getDoc(key: docKey) {
            localState = await doc.encodeStateAsUpdate()
        } else if let snapshot = try? await store.loadSnapshot(docKey: docKey) {
            localState = snapshot.state
        }
        let localBytes = localState?.count ?? 0
        let localLooksNonEmpty = localBytes > 2

        if serverLooksEmpty && localLooksNonEmpty, let localState {
            let documentKind = recipeId == ShoppingListConstants.offlineRecipeId
                ? ShoppingListConstants.documentKind
                : nil
            await emitSyncRequest(
                recipeId: recipeId,
                update: localState,
                docKey: docKey,
                documentKind: documentKind
            )
            return
        }

        if localLooksNonEmpty {
            try await documentManager.applyUpdate(
                key: docKey,
                data: stateData,
                lastSyncedAt: lastSyncedAt
            )
            logger.info("Merged server document into \(docKey) (\(stateData.count) bytes)")
        } else {
            try await documentManager.replaceDocument(
                key: docKey,
                state: stateData,
                lastSyncedAt: lastSyncedAt
            )
        }
    }

    private func handleDocumentLoaded(recipeId: String, stateData: Data, lastSyncedAt: String?) async {
        let docKey = docKeyFor(recipeId: recipeId)
        logger.info("document_loaded: \(docKey), \(stateData.count) bytes")
        lastSuccessfulSyncAt = Date()

        do {
            try await applyServerDocumentState(
                recipeId: recipeId,
                docKey: docKey,
                stateData: stateData,
                lastSyncedAt: lastSyncedAt
            )
        } catch {
            logger.error("Failed to apply document state for \(docKey): \(error)")
        }

        if recipeId == ShoppingListConstants.offlineRecipeId {
            await refreshShoppingSnapshot()
        } else if recipeId == "collection" {
            await refreshCollectionEntries()
        } else {
            await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
        }
    }

    private func handleDocumentsLoaded(documents: [(String, Data, String?)]) async {
        var shouldRefreshCollection = false
        var loadedRecipeIds: [String] = []
        if !documents.isEmpty { lastSuccessfulSyncAt = Date() }
        for (recipeId, stateData, lastSyncedAt) in documents {
            let docKey = docKeyFor(recipeId: recipeId)
            do {
                try await applyServerDocumentState(
                    recipeId: recipeId,
                    docKey: docKey,
                    stateData: stateData,
                    lastSyncedAt: lastSyncedAt
                )
                if recipeId == "collection" {
                    shouldRefreshCollection = true
                } else if recipeId != ShoppingListConstants.offlineRecipeId {
                    loadedRecipeIds.append(recipeId)
                }
            } catch {
                logger.error("Failed to apply batch doc \(docKey): \(error)")
            }
        }
        if shouldRefreshCollection {
            await refreshCollectionEntries()
        }
        if documents.contains(where: { $0.0 == ShoppingListConstants.offlineRecipeId }) {
            await refreshShoppingSnapshot()
        }
        if !loadedRecipeIds.isEmpty {
            recipeBatchLoadCompleted += loadedRecipeIds.count
            if recipeBatchLoadCompleted >= recipeBatchLoadTotal {
                recipeBatchLoadInFlight = false
            }
            await refreshRecipeDocumentCacheStatus()
        }
        if let active = activeRecipeId, loadedRecipeIds.contains(active) {
            await refreshCurrentRecipe(recipeId: active)
        }
    }

    /// Batch-fetch recipe Y.Docs missing from SQLite (web: `load_documents` after collection sync).
    private func scheduleRecipeDocumentsBatchLoad(recipeIds: [String]) {
        guard connectionState == .connected, isSocketAuthenticated else { return }
        guard socket?.status == .connected else { return }
        recipeBatchLoadTask?.cancel()
        recipeBatchLoadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.emitRecipeDocumentsBatchLoad(recipeIds: recipeIds)
        }
    }

    private func emitRecipeDocumentsBatchLoad(recipeIds: [String]) async {
        guard connectionState == .connected, isSocketAuthenticated else { return }
        guard socket?.status == .connected else { return }
        let missing = await recipeIdsMissingLocalSnapshots(recipeIds)
        guard !missing.isEmpty else {
            recipeBatchLoadInFlight = false
            recipeBatchLoadTotal = 0
            recipeBatchLoadCompleted = 0
            await refreshRecipeDocumentCacheStatus()
            return
        }
        recipeBatchLoadInFlight = true
        recipeBatchLoadTotal = missing.count
        recipeBatchLoadCompleted = 0
        await refreshRecipeDocumentCacheStatus()
        socket?.emit("load_documents", ["recipeIds": missing])
        logger.info("Emitted load_documents for \(missing.count) recipes")
    }

    private func recipeIdsMissingLocalSnapshots(_ recipeIds: [String]) async -> [String] {
        guard let userId else { return [] }
        var missing: [String] = []
        for recipeId in recipeIds {
            let key = "\(userId):recipe:\(recipeId)"
            if (try? await store.loadSnapshot(docKey: key)) == nil {
                missing.append(recipeId)
            }
        }
        return missing
    }

    private func handleRecipeUpdated(recipeId: String, updateData: Data) async {
        let docKey = docKeyFor(recipeId: recipeId)
        logger.debug("recipe_updated: \(docKey), \(updateData.count) bytes")
        lastSuccessfulSyncAt = Date()

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

        descriptionEditorSessions[recipeId]?.bridge?.applyRemoteUpdate(updateData)
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

    private func handleShoppingListUpdated(updateData: Data) async {
        guard let userId else { return }
        let key = Self.shoppingDocKey(userId: userId)
        logger.debug("shopping_list_updated: \(updateData.count) bytes")
        lastSuccessfulSyncAt = Date()
        do {
            try await documentManager.applyUpdate(key: key, data: updateData)
        } catch {
            logger.error("Failed to apply shopping list update: \(error)")
        }
        await refreshShoppingSnapshot()
    }

    func refreshShoppingSnapshot() async {
        do {
            shoppingSnapshot = try await documentManager.readShoppingListSnapshot()
        } catch {
            logger.error("Failed to read shopping list: \(error)")
        }
    }

    #if DEBUG
    /// Smoke test helper (same snapshot read as UI).
    func refreshShoppingSnapshotForSmokeTest() async {
        await refreshShoppingSnapshot()
    }

    /// Loads local SQLite docs for smoke test without waiting on socket `start()` to finish.
    func readRecipeDataForShopping(recipeId: String) async throws -> RecipeData? {
        guard let userId else { return nil }
        _ = try? await documentManager.getOrCreateDoc(key: docKeyFor(recipeId: recipeId))
        return try await documentManager.readRecipeData(recipeId: recipeId, userId: userId)
    }

    func prepareForShoppingSmokeTest(userId: String) async {
        ShoppingSmokeTest.writeProgress("prepareStart")
        self.userId = userId
        await documentManager.setUserId(userId)
        ShoppingSmokeTest.writeProgress("prepareUserId")
        await installChangeHandlersIfNeeded()
        ShoppingSmokeTest.writeProgress("prepareHandlers")
        let collectionKey = "\(userId):collection"
        if (try? await documentManager.getOrCreateDoc(key: collectionKey)) != nil,
           let entries = try? await documentManager.readCollectionEntries() {
            collectionEntries = entries.filter { !$0.deleted }
        }
        ShoppingSmokeTest.writeProgress(
            "prepareCollection",
            extra: ["collectionLoaded": !collectionEntries.isEmpty]
        )
        ShoppingSmokeTest.writeProgress(
            "prepareDone",
            itemCount: shoppingSnapshot.items.count,
            extra: ["collectionLoaded": !collectionEntries.isEmpty]
        )
    }
    #endif

    // MARK: - Recipe document cache

    /// Re-fetch recipe Y.Docs missing from SQLite when online.
    func retryRecipeDocumentsBatchLoad() {
        scheduleRecipeDocumentsBatchLoad(recipeIds: collectionEntries.map(\.id))
    }

    func refreshRecipeDocumentCacheStatus() async {
        guard let userId else {
            recipeDocumentCacheStatus = RecipeDocumentCacheStatus()
            return
        }
        let entries = collectionEntries
        var cached = 0
        var pending: [RecipeDocumentCachePendingEntry] = []
        for entry in entries {
            let key = "\(userId):recipe:\(entry.id)"
            if (try? await store.loadSnapshot(docKey: key)) != nil {
                cached += 1
            } else {
                pending.append(RecipeDocumentCachePendingEntry(id: entry.id, name: entry.name))
            }
        }
        let downloadTotal = recipeBatchLoadInFlight
            ? max(recipeBatchLoadTotal, pending.count)
            : pending.count
        recipeDocumentCacheStatus = RecipeDocumentCacheStatus(
            totalRecipes: entries.count,
            cachedRecipes: cached,
            isDownloading: recipeBatchLoadInFlight,
            downloadCompleted: recipeBatchLoadCompleted,
            downloadTotal: downloadTotal,
            pendingEntries: pending
        )
    }

    // MARK: - Recipe image prefetch

    /// Re-download missing preview/full files when online.
    func retryImagePrefetch() {
        scheduleImagePrefetch(for: collectionEntries)
    }

    func refreshImageCacheStatus() async {
        let status = await RecipeImageService.shared.cacheStatus(for: collectionEntries)
        imageCacheStatus = status
    }

    private func scheduleImageCacheStatusRefresh() {
        imageCacheStatusRefreshTask?.cancel()
        imageCacheStatusRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshImageCacheStatus()
        }
    }

    private func installImageCacheObserversIfNeeded() {
        guard !imageCacheObserversInstalled else { return }
        imageCacheObserversInstalled = true
        let names: [Notification.Name] = [
            .recipeImageDidCache,
            .recipeImageCacheStatusDidChange,
            .recipeImagePrefetchDidUpdate,
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleImageCacheStatusRefresh()
            }
        }
    }

    private func scheduleImagePrefetch(for entries: [CollectionEntry]) {
        let allowNetwork = connectionState == .connected
        scheduleImageCacheStatusRefresh()
        Task {
            await RecipeImageService.shared.prefetchPreviews(
                entries: entries,
                allowNetwork: allowNetwork
            )
            await refreshImageCacheStatus()
        }
    }

    // MARK: - Collection Reading

    private func refreshCollectionEntries() async {
        do {
            let entries = try await documentManager.readCollectionEntries()
            let filtered = entries.filter { !$0.deleted }
            if let recipeId = activeRecipeId,
               !filtered.contains(where: { $0.id == recipeId }),
               entries.contains(where: { $0.id == recipeId && $0.deleted }) {
                currentRecipe = nil
                activeRecipeId = nil
                activeRecipeWasRemoved = true
            }
            collectionEntries = filtered
            // Rebuild the derived collections index and refresh folders so the
            // collections view stays in sync after any recipes change.
            collectionIndex = CollectionRecipesIndexBuilder.build(from: filtered)
            await refreshFolders()
            syncActiveRecipeFromCollection()
            scheduleImagePrefetch(for: filtered)
            scheduleRecipeDocumentsBatchLoad(recipeIds: filtered.map(\.id))
            await refreshImageCacheStatus()
            await refreshRecipeDocumentCacheStatus()
            logger.info("Collection refreshed: \(filtered.count) active entries (total \(entries.count))")
        } catch {
            logger.error("Failed to read collection entries: \(error)")
        }
    }

    private func collectionEntry(for recipeId: String) -> CollectionEntry? {
        collectionEntries.first { $0.id == recipeId }
    }

    /// Re-read active folders from the collection doc.
    /// Called after `refreshCollectionEntries` and after each folder mutation.
    private func refreshFolders() async {
        do {
            let active = try await documentManager.readFolders()
            folders = active
        } catch {
            logger.error("Failed to read folders: \(error)")
        }
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

        await documentManager.applyOfflineQueueToLocalDocs()

        if (try? await documentManager.getOrCreateDoc(key: collectionKey)) != nil {
            await refreshCollectionEntries()
            logger.info("Loaded collection from local snapshot")
        }

        let shoppingKey = Self.shoppingDocKey(userId: userId)
        if (try? await documentManager.getOrCreateDoc(key: shoppingKey)) != nil {
            await refreshShoppingSnapshot()
            logger.info("Loaded shopping list from local snapshot")
        }
        isLocalDataLoaded = true
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
        await documentManager.setShoppingHandlers(
            onChanged: { [weak self] in
                Task { @MainActor in
                    await self?.refreshShoppingSnapshot()
                }
            },
            onLocalUpdate: { [weak self] update in
                await self?.handleLocalShoppingUpdate(update: update)
            }
        )
    }

    private func refreshCurrentRecipeIfAllowed(recipeId: String) async {
        guard recipeRefreshSuspended == 0 else { return }
        await refreshCurrentRecipe(recipeId: recipeId)
    }

    func refreshCurrentRecipe(recipeId: String) async {
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
        isPublic: Bool? = nil,
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
            isPublic: isPublic,
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
            setConnectionState(.error(message), reason: "sync_error_ownership")
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
        hasRequestedShoppingLoad = false
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

    private static func shoppingDocKey(userId: String) -> String {
        "\(userId):shoppingList"
    }

    private func docKeyFor(recipeId: String) -> String {
        guard let userId else { return recipeId }
        if recipeId == "collection" {
            return "\(userId):collection"
        }
        if recipeId == ShoppingListConstants.offlineRecipeId {
            return Self.shoppingDocKey(userId: userId)
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
