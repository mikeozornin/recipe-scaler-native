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
    @Published private(set) var shoppingSnapshot: ShoppingListSnapshot = .empty
    @Published private(set) var currentRecipe: RecipeData?
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var writeSyncStates: [String: WriteSyncState] = [:]
    @Published var syncErrorMessage: String?
    @Published private(set) var activeRecipeWasRemoved = false
    @Published private(set) var imageCacheStatus = RecipeImageCacheStatus()

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
    private var connectingWatchdogTask: Task<Void, Never>?
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

    func removeShoppingItem(id: String) async throws {
        try await documentManager.removeShoppingItem(id: id)
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
        // #region agent log
        logSyncConnection(
            hypothesisId: "D",
            location: "YjsSyncService.swift:start",
            message: "start_enter",
            data: [
                "userId": userId,
                "priorUserId": self.userId ?? "nil",
                "connectionState": String(describing: connectionState),
            ]
        )
        // #endregion
        let isSameUser = self.userId == userId
        if !isSameUser, self.userId != nil {
            await documentManager.clearOfflineQueueForAccountSwitch()
            writeSyncStates = [:]
        }
        self.userId = userId
        await documentManager.setUserId(userId)
        APIClient.shared.configure(userId: userId)
        installImageCacheObserversIfNeeded()

        // Connect before SQLite snapshot IO so UI is not stuck on "Offline" while docs load.
        beginSocketSession(isSameUser: isSameUser, userId: userId)

        // #region agent log
        logSyncConnection(
            hypothesisId: "D",
            location: "YjsSyncService.swift:start",
            message: "socket_session_begun",
            data: [
                "userId": userId,
                "isSameUser": String(isSameUser),
                "socketStatus": socket.map { String(describing: $0.status) } ?? "nil",
                "connectionState": String(describing: connectionState),
            ]
        )
        // #endregion

        await loadLocalSnapshots()

        // #region agent log
        logSyncConnection(
            hypothesisId: "D",
            location: "YjsSyncService.swift:start",
            message: "local_snapshots_loaded",
            data: [
                "userId": userId,
                "connectionState": String(describing: connectionState),
            ]
        )
        // #endregion
    }

    private func beginSocketSession(isSameUser: Bool, userId: String) {
        if isSameUser {
            // Re-login with the same account: always open a fresh socket (avoids stale session).
            if socket != nil {
                connectSocket()
            } else {
                resumeSocketSession()
            }
            return
        }

        logger.info("Starting YjsSync for user \(userId)")
        connectSocket()
    }

    /// Reconcile socket after `start` is called again for the same account (view re-appear, etc.).
    private func resumeSocketSession() {
        guard let socket else {
            // #region agent log
            logSyncConnection(
                hypothesisId: "E",
                location: "YjsSyncService.swift:resumeSocketSession",
                message: "no_socket_reconnect",
                data: ["connectionState": String(describing: connectionState)]
            )
            // #endregion
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
            // #region agent log
            logSyncConnection(
                hypothesisId: "E",
                location: "YjsSyncService.swift:resumeSocketSession",
                message: "already_connecting_skip",
                data: ["connectionState": String(describing: connectionState)]
            )
            // #endregion
            break
        case .notConnected, .disconnected:
            // #region agent log
            logSyncConnection(
                hypothesisId: "E",
                location: "YjsSyncService.swift:resumeSocketSession",
                message: "socket_down_reconnect",
                data: [
                    "socketStatus": String(describing: socket.status),
                    "connectionState": String(describing: connectionState),
                ]
            )
            // #endregion
            connectSocket()
        }
    }

    /// Load a recipe document from local snapshot and sync with the server.
    func loadRecipe(recipeId: String) async {
        guard let userId else { return }
        let loadStart = CFAbsoluteTimeGetCurrent()
        activeRecipeId = recipeId
        // #region agent log
        AgentSyncDebugLog.write(
            hypothesisId: "F",
            location: "YjsSyncService.swift:loadRecipe",
            message: "start",
            data: ["recipeId": recipeId]
        )
        // #endregion
        await installChangeHandlersIfNeeded()

        let docKey = docKeyFor(recipeId: recipeId)
        _ = try? await documentManager.getOrCreateDoc(key: docKey)
        await refreshCurrentRecipe(recipeId: recipeId)

        // #region agent log
        AgentSyncDebugLog.write(
            hypothesisId: "F",
            location: "YjsSyncService.swift:loadRecipe",
            message: "after_refresh",
            data: [
                "recipeId": recipeId,
                "ms": String(Int((CFAbsoluteTimeGetCurrent() - loadStart) * 1000)),
                "hasCurrentRecipe": String(currentRecipe != nil),
                "currentRecipeId": currentRecipe?.id ?? "nil",
                "ingredientCount": String(currentRecipe?.ingredients.count ?? 0),
            ]
        )
        // #endregion

        guard socket?.status == .connected, isSocketAuthenticated else { return }
        socket?.emit("load_document", ["recipeId": recipeId])
        logger.info("Emitted load_document for recipe \(recipeId)")
    }

    /// Stop synchronization and clean up.
    func stop() {
        logger.info("Stopping YjsSync")
        // #region agent log
        logSyncConnection(
            hypothesisId: "A",
            location: "YjsSyncService.swift:stop",
            message: "stop_called",
            data: [
                "userId": userId ?? "nil",
                "connectionState": String(describing: connectionState),
            ]
        )
        // #endregion
        teardownSocket()
        connectionState = .disconnected
        userId = nil
        activeRecipeId = nil
        currentRecipe = nil
        shoppingSnapshot = .empty
    }

    // MARK: - Socket.IO Connection

    private func teardownSocket() {
        collectionLoadTask?.cancel()
        collectionLoadTask = nil
        connectingWatchdogTask?.cancel()
        connectingWatchdogTask = nil
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
        // #region agent log
        logSyncConnection(
            hypothesisId: "B",
            location: "YjsSyncService.swift:connectSocket",
            message: "connect_begin",
            data: [
                "sessionId": sessionId.uuidString,
                "userId": userId,
                "baseURL": Config.baseURL,
            ]
        )
        // #endregion

        teardownSocket()

        isSocketAuthenticated = false
        hasRequestedCollectionLoad = false
        hasRequestedShoppingLoad = false
        collectionLoadTask?.cancel()
        collectionLoadTask = nil
        let serverURL = URL(string: Config.baseURL)!
        // Web client Yjs uses websocket-only; polling long-poll drops on iOS (-1005) and poisons reconnect.
        manager = SocketManager(socketURL: serverURL, config: [
            .log(false),
            .compress,
            .forceWebsockets(true),
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWait(1000),
            .reconnectWaitMax(5000),
            .connectParams(["userId": userId, "deviceId": deviceId]),
        ])

        let client = manager!.defaultSocket
        self.socket = client

        // Socket lifecycle handlers
        client.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                self.logger.info("Socket.IO connected")
                // #region agent log
                self.logSyncConnection(
                    hypothesisId: "C",
                    location: "YjsSyncService.swift:socket.connect",
                    message: "engine_connected",
                    data: [
                        "sessionId": sessionId.uuidString,
                        "socketStatus": self.socket.map { String(describing: $0.status) } ?? "nil",
                    ]
                )
                // #endregion
                self.connectionState = .connecting
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
                    // #region agent log
                    self.logSyncConnection(
                        hypothesisId: "C",
                        location: "YjsSyncService.swift:socket.connected",
                        message: "ack_ignored_no_message",
                        data: ["sessionId": sessionId.uuidString]
                    )
                    // #endregion
                    return
                }
                self.collectionLoadTask?.cancel()
                self.logger.info("Socket.IO authenticated (server ack)")
                // #region agent log
                self.logSyncConnection(
                    hypothesisId: "C",
                    location: "YjsSyncService.swift:socket.connected",
                    message: "auth_ack",
                    data: ["sessionId": sessionId.uuidString]
                )
                // #endregion
                self.markAuthenticatedAndLoadCollection()
            }
        }

        client.on("auth_error") { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                let message = data.first as? [String: Any]
                let detail = message?["message"] as? String ?? "Authentication failed"
                self.logger.error("Socket.IO auth_error: \(detail)")
                // #region agent log
                self.logSyncConnection(
                    hypothesisId: "C",
                    location: "YjsSyncService.swift:socket.auth_error",
                    message: "auth_error",
                    data: ["sessionId": sessionId.uuidString, "detail": detail]
                )
                // #endregion
                self.connectionState = .error(detail)
            }
        }

        client.on(clientEvent: .disconnect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isCurrentSocketSession(sessionId) else {
                    // #region agent log
                    self.logSyncConnection(
                        hypothesisId: "A",
                        location: "YjsSyncService.swift:socket.disconnect",
                        message: "stale_disconnect_ignored",
                        data: [
                            "staleSessionId": sessionId.uuidString,
                            "activeSessionId": self.socketSessionId.uuidString,
                        ]
                    )
                    // #endregion
                    return
                }
                self.logger.info("Socket.IO disconnected")
                // #region agent log
                self.logSyncConnection(
                    hypothesisId: "A",
                    location: "YjsSyncService.swift:socket.disconnect",
                    message: "disconnect_applied",
                    data: ["sessionId": sessionId.uuidString]
                )
                // #endregion
                self.isSocketAuthenticated = false
                self.hasRequestedCollectionLoad = false
                self.hasRequestedShoppingLoad = false
                self.collectionLoadTask?.cancel()
                self.collectionLoadTask = nil
                self.disconnectTimestamp = Date()
                // Auto-reconnect is enabled — show reconnecting, not "Offline".
                self.connectionState = .reconnecting
            }
        }

        client.on(clientEvent: .reconnectAttempt) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                self.isSocketAuthenticated = false
                self.hasRequestedCollectionLoad = false
                self.hasRequestedShoppingLoad = false
                self.connectionState = .reconnecting
            }
        }

        // Auth is emitted from `.connect` only — `reconnect` fires before the engine is ready.
        client.on(clientEvent: .reconnect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                self.logger.info("Socket.IO reconnected (awaiting connect for auth)")
                self.connectionState = .connecting
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
                // #region agent log
                self.logSyncConnection(
                    hypothesisId: "B",
                    location: "YjsSyncService.swift:socket.error",
                    message: "socket_error",
                    data: [
                        "sessionId": sessionId.uuidString,
                        "detail": msg,
                        "recoverable": String(self.isRecoverableSocketError(msg)),
                    ]
                )
                // #endregion
                if self.isRecoverableSocketError(msg) {
                    self.isSocketAuthenticated = false
                    self.connectionState = .reconnecting
                } else {
                    self.connectionState = .error(msg)
                }
            }
        }

        // Register sync protocol event handlers
        eventHandler.registerHandlers(on: client)
        client.connect()
        connectionState = .connecting
    }

    private func isCurrentSocketSession(_ sessionId: UUID) -> Bool {
        socketSessionId == sessionId
    }

    private func logSyncConnection(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String]
    ) {
        AgentSyncDebugLog.write(
            hypothesisId: hypothesisId,
            location: location,
            message: message,
            data: data
        )
    }

    private func emitAuth() {
        guard let userId else { return }
        let sessionAtEmit = socketSessionId

        if performAuthEmit(userId: userId) {
            return
        }

        // `.connect` can fire before `status == .connected` — retry briefly (was causing infinite "Connecting…").
        // #region agent log
        logSyncConnection(
            hypothesisId: "G",
            location: "YjsSyncService.swift:emitAuth",
            message: "auth_emit_deferred",
            data: ["socketStatus": socket.map { String(describing: $0.status) } ?? "nil"]
        )
        // #endregion
        Task { @MainActor [weak self] in
            for attempt in 1...15 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, self.isCurrentSocketSession(sessionAtEmit) else { return }
                if self.performAuthEmit(userId: userId) {
                    // #region agent log
                    self.logSyncConnection(
                        hypothesisId: "G",
                        location: "YjsSyncService.swift:emitAuth",
                        message: "auth_emit_retry_ok",
                        data: ["attempt": String(attempt)]
                    )
                    // #endregion
                    return
                }
            }
            // #region agent log
            self?.logSyncConnection(
                hypothesisId: "G",
                location: "YjsSyncService.swift:emitAuth",
                message: "auth_emit_retry_exhausted",
                data: ["socketStatus": self?.socket.map { String(describing: $0.status) } ?? "nil"]
            )
            // #endregion
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

    /// Escapes prolonged `.connecting` when auth emit/ack never completes.
    private func scheduleConnectingWatchdog(sessionId: UUID) {
        connectingWatchdogTask?.cancel()
        connectingWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            await MainActor.run {
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                guard !self.isSocketAuthenticated else { return }
                guard case .connecting = self.connectionState else { return }
                self.logger.warning("Connecting watchdog fired — forcing auth retry")
                // #region agent log
                self.logSyncConnection(
                    hypothesisId: "G",
                    location: "YjsSyncService.swift:connectingWatchdog",
                    message: "watchdog_fired",
                    data: ["socketStatus": self.socket.map { String(describing: $0.status) } ?? "nil"]
                )
                // #endregion
                self.scheduleCollectionLoadAfterAuth()
                self.emitAuth()
            }
        }
    }

    /// Transient transport failures while Socket.IO auto-reconnects — do not surface as hard sync errors.
    private func isRecoverableSocketError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        if normalized == "error" { return true }
        let recoverableFragments = [
            "network connection was lost",
            "request timed out",
            "not connected",
            "tried emitting when not connected",
            "could not connect",
            "connection lost",
        ]
        return recoverableFragments.contains { normalized.contains($0) }
    }

    /// Server `auth` runs async (validate/repair). Load collection after a short delay or sooner on server `connected` ack.
    private func scheduleCollectionLoadAfterAuth() {
        collectionLoadTask?.cancel()
        collectionLoadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                guard let self else { return }
                if self.isSocketAuthenticated { return }
                guard self.socket != nil else { return }
                self.logger.warning("Socket auth ack timeout; loading collection after delay")
                // #region agent log
                self.logSyncConnection(
                    hypothesisId: "G",
                    location: "YjsSyncService.swift:scheduleCollectionLoadAfterAuth",
                    message: "auth_ack_timeout_fallback",
                    data: ["socketStatus": self.socket.map { String(describing: $0.status) } ?? "nil"]
                )
                // #endregion
                self.markAuthenticatedAndLoadCollection()
            }
        }
    }

    private func markAuthenticatedAndLoadCollection() {
        connectingWatchdogTask?.cancel()
        connectingWatchdogTask = nil
        isSocketAuthenticated = true
        connectionState = .connected
        // #region agent log
        logSyncConnection(
            hypothesisId: "C",
            location: "YjsSyncService.swift:markAuthenticatedAndLoadCollection",
            message: "connection_state_connected",
            data: ["sessionId": socketSessionId.uuidString]
        )
        // #endregion
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

        if socket?.status == .connected, isSocketAuthenticated {
            writeSyncStates[recipeId] = .syncing
            await emitSyncRequest(recipeId: recipeId, update: update, docKey: docKey)
        } else {
            writeSyncStates[recipeId] = .queued
            try? await offlineQueue.enqueue(docKey: docKey, recipeId: recipeId, yjsUpdate: update)
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
        // Collection sync matches web: omit `recipeId` (server treats as collection doc).
        if recipeId != "collection" {
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
        // #region agent log
        AgentSyncDebugLog.write(
            hypothesisId: "B",
            location: "YjsSyncService.swift:emitSyncRequest",
            message: "sync_request emitted",
            data: [
                "target": target,
                "payloadBytes": String(update.count),
                "includesRecipeId": String(recipeId != "collection"),
                "hasLastSyncedAt": String(lastSyncedAt != nil),
            ]
        )
        // #endregion
    }

    private func handleSyncConfirmed(recipeId: String, lastSyncedAt: String?) async {
        guard recipeId != "unknown" else { return }
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
                try await documentManager.replaceDocument(
                    key: docKey,
                    state: stateData,
                    lastSyncedAt: lastSyncedAt
                )
            }
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
                    try await documentManager.replaceDocument(
                        key: docKey,
                        state: stateData,
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
        do {
            try await documentManager.applyUpdate(key: key, data: updateData)
        } catch {
            logger.error("Failed to apply shopping list update: \(error)")
        }
        await refreshShoppingSnapshot()
    }

    private func refreshShoppingSnapshot() async {
        do {
            shoppingSnapshot = try await documentManager.readShoppingListSnapshot()
        } catch {
            logger.error("Failed to read shopping list: \(error)")
        }
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
            syncActiveRecipeFromCollection()
            scheduleImagePrefetch(for: filtered)
            await refreshImageCacheStatus()
            logger.info("Collection refreshed: \(filtered.count) active entries (total \(entries.count))")
            #if DEBUG
            if let userId, RecipeReadDiagnostics.launchRecipeId() != nil {
                await RecipeReadDiagnostics.runAfterCollectionLoad(
                    documentManager: documentManager,
                    userId: userId
                )
            }
            #endif
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

        let shoppingKey = Self.shoppingDocKey(userId: userId)
        if (try? await documentManager.getOrCreateDoc(key: shoppingKey)) != nil {
            await refreshShoppingSnapshot()
            logger.info("Loaded shopping list from local snapshot")
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
            // #region agent log
            AgentSyncDebugLog.write(
                hypothesisId: "E",
                location: "YjsSyncService.swift:refreshCurrentRecipe",
                message: "error",
                data: ["recipeId": recipeId, "error": error.localizedDescription]
            )
            // #endregion
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
