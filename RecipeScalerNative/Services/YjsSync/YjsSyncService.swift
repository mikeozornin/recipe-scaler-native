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
/// UI binds to `@Observable collectionEntries` and `@Observable connectionState`.
@MainActor
@Observable
final class YjsSyncService {
    private(set) var collectionEntries: [CollectionEntry] = []
    /// Active (non-deleted) folders from the collection doc, sorted for display.
    private(set) var folders: [RecipeFolder] = []
    /// Derived in-memory index for the collections view.
    private(set) var collectionIndex: CollectionRecipesIndex = .empty
    private(set) var shoppingSnapshot: ShoppingListSnapshot = .empty
    private(set) var currentRecipe: RecipeData?
    /// Whether the initial local snapshot load has completed. Used by collection views
    /// to avoid rendering empty state during cold start.
    private(set) var isLocalDataLoaded = false
    private(set) var connectionState: ConnectionState = .disconnected
    /// Polling-first matches PWA `websocket-service` and avoids Starscream direct-WSS hangs on iOS.
    private(set) var connectionTransport: SyncConnectionTransport = .pollingAndWebsocket
    private(set) var writeSyncStates: [String: WriteSyncState] = [:]
    var syncErrorMessage: String?
    private(set) var activeRecipeWasRemoved = false
    private(set) var imageCacheStatus = RecipeImageCacheStatus()
    private(set) var recipeDocumentCacheStatus = RecipeDocumentCacheStatus()
    private(set) var lastSuccessfulSyncAt: Date?
    /// Read-mode reconnect: headless WebView export when queue/wire push is insufficient.
    private(set) var descriptionWireExportRecipeIds: Set<String> = []

    func acknowledgeRecipeRemoved() {
        activeRecipeWasRemoved = false
    }

    private let documentManager: DocumentManager
    private let store: YDocStore
    private let offlineQueue: OfflineWriteQueue
    private let eventHandler: SyncEventHandler

    /// Injected dependencies (review #27 — were previously reached via `.shared`).
    private let timerSync: TimerSyncService
    private let pushRegistration: PushRegistrationService
    private let recipeImage: RecipeImageService
    private let yjsMergeHelper: YjsMergeHelper
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    /// Guards socket handlers: stale clients must not overwrite `connectionState` after reconnect.
    private enum ConnectionStep: Equatable, Sendable {
        case disconnected
        case connecting(sessionId: UUID)
        case authenticating(sessionId: UUID)
        case authenticated(sessionId: UUID)
    }

    private var connectionStep: ConnectionStep = .disconnected
    /// FSM watchdog: engine-connect timeout (8s) или auth-ack timeout (2s).
    /// Единственный владелец — `transition(to:)`. Не использовать вне переходов
    /// FSM-step — иначе network-debounce отменяет watchdog при сетевом мерцании
    /// (регрессия, описанная в MIK-161).
    private var connectionStepTimer: Task<Void, Never>?
    /// Debounce network-regain (400ms) перед `reconnectAfterNetworkRegained`.
    /// Не зависит от `connectionStep`: сеть может вернуться в любом FSM-состоянии.
    private var networkReconnectDebounceTask: Task<Void, Never>?
    private var socketSessionId: UUID? {
        switch connectionStep {
        case .disconnected:
            return nil
        case .connecting(let id), .authenticating(let id), .authenticated(let id):
            return id
        }
    }
    private let logger = Logger(subsystem: "com.recipescaler.native", category: "YjsSyncService")

    private var userId: String?
    private let deviceId: String
    private var isSocketAuthenticated = false
    /// Guards against duplicate `auth` emits within a single socket session.
    /// `emitAuth()` has three call sites (`.connect` handler, `resumeSocketSession`,
    /// `handleStuckEngineConnect`); without this flag, concurrent triggers would
    /// emit `auth` twice and the server would ack twice — producing the duplicate
    /// "Emitted auth" / "Socket.IO authenticated" log lines observed on cold start.
    private var didEmitAuthThisSession = false
    private var hasRequestedCollectionLoad = false
    private var hasRequestedShoppingLoad = false
    private var recipeBatchLoadTask: Task<Void, Never>?
    private var recipeBatchLoadInFlight = false
    private var recipeBatchLoadCompleted = 0
    private var recipeBatchLoadTotal = 0

    private var activeRecipeId: String?
    private var disconnectTimestamp: Date?
    private var pendingReconnectSyncTask: Task<Void, Never>?
    private var changeHandlersInstalled = false
    private var localUpdateHandlerInstalled = false
    private var recipeRefreshSuspended = 0
    @ObservationIgnored private var _updateDebouncer: UpdateDebouncer?
    private var updateDebouncer: UpdateDebouncer {
        if let _updateDebouncer {
            return _updateDebouncer
        }
        let d = UpdateDebouncer { [weak self] recipeId, update in
            await self?.sendDebouncedUpdate(recipeId: recipeId, update: update)
        }
        _updateDebouncer = d
        return d
    }
    private var imageCacheStatusRefreshTask: Task<Void, Never>?
    private var collectionEntriesRefreshTask: Task<Void, Never>?
    private var imageCacheObserversInstalled = false
    private var descriptionEditorSessions: [String: DescriptionEditorSession] = [:]
    private var networkPathMonitor: NWPathMonitor?
    private var wireSnapshotRefreshTasks: [String: Task<Void, Never>] = [:]
    private var documentLoadContinuations: [String: CheckedContinuation<Bool, Never>] = [:]
    private var documentLoadTasks: [String: Task<Bool, Never>] = [:]
    private var isNetworkReachable = true

    /// Deterministic replacement for the old `localBytes > serverBytes + 128` heuristic.
    ///
    /// A recipe is "unsynced / local-ahead" iff it carries an explicit flag set on every local
    /// write and cleared only on `sync_confirmed`. The set is persisted in SQLite
    /// (`recipe_sync_state`, MIK-128) so it survives an app kill (closes the cold-start gap
    /// the byte heuristic tried to guess at), and CRDT byte sizes never feed the decision —
    /// removing the false "local ahead" that wedged a doc into perpetual skip-pull after a merge.
    private var unsyncedRecipeIds: Set<String> = []

    /// docKey → offline queue row IDs included in the last emitted drain batch awaiting `sync_confirmed`.
    private var inFlightOfflineEntryIdsByDocKey: [String: Set<Int64>] = [:]

    /// When the current in-flight batch for `docKey` was marked (for silent-stall TTL retry).
    private var inFlightOfflineStartedAtByDocKey: [String: Date] = [:]

    private static let offlineInFlightTimeout: TimeInterval = 30

    /// Load unsynced flags from SQLite. Replaces the old plist array
    /// `unsyncedRecipeIds:{userId}` (one shared set was previously scoped per user via the
    /// plist key; now the table is wiped on logout via `store.deleteAll()`).
    private func loadUnsyncedRecipeIds() async {
        let stored = (try? await store.loadUnsyncedRecipeIds()) ?? []
        unsyncedRecipeIds = stored
    }

    /// MIK-128 one-time data migration: move the old `unsyncedRecipeIds:{userId}` plist
    /// array into `recipe_sync_state` and drop the dead-write `lastServerDocBytes:{recipeId}`
    /// keys. Idempotent — guarded by a per-user plist flag so it runs exactly once.
    private func migratePlistSyncKeysIfNeeded(userId: String) async {
        let migrationFlag = "mik128_sync_keys_migrated:\(userId)"
        guard !UserDefaults.standard.bool(forKey: migrationFlag) else { return }

        // Port unsynced flags from the legacy per-user plist array.
        let legacyKey = "unsyncedRecipeIds:\(userId)"
        if let stored = UserDefaults.standard.array(forKey: legacyKey) as? [String] {
            for recipeId in stored {
                try? await store.setRecipeUnsynced(recipeId: recipeId, unsynced: true)
            }
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }

        // Sweep the dead-write `lastServerDocBytes:{recipeId}` keys left over by
        // earlier app versions (never cleaned on logout). Use the app's scoped
        // persistent domain instead of dictionaryRepresentation() to avoid
        // materializing the entire (system + app) defaults domain.
        let legacyBytesPrefix = "lastServerDocBytes:"
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let appDomain = UserDefaults.standard.persistentDomain(forName: bundleId) ?? [:]
        let staleKeys = appDomain.keys.filter { $0.hasPrefix(legacyBytesPrefix) }
        for key in staleKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        UserDefaults.standard.set(true, forKey: migrationFlag)
    }

    /// Flag a recipe as having local edits the server has not confirmed yet.
    private func markRecipeUnsynced(_ recipeId: String) async {
        guard isRecipeDocument(recipeId: recipeId) else { return }
        guard unsyncedRecipeIds.insert(recipeId).inserted else { return }
        try? await store.setRecipeUnsynced(recipeId: recipeId, unsynced: true)
    }

    /// Clear the unsynced flag once the server acknowledges the recipe (`sync_confirmed`/delete).
    private func markRecipeSynced(_ recipeId: String) async {
        guard unsyncedRecipeIds.remove(recipeId) != nil else { return }
        try? await store.setRecipeUnsynced(recipeId: recipeId, unsynced: false)
    }

    init(
        store: YDocStore,
        timerSync: TimerSyncService,
        pushRegistration: PushRegistrationService,
        recipeImage: RecipeImageService,
        yjsMergeHelper: YjsMergeHelper
    ) {
        self.store = store
        self.offlineQueue = OfflineWriteQueue(store: store)
        self.documentManager = DocumentManager(store: store)
        self.eventHandler = SyncEventHandler()
        self.timerSync = timerSync
        self.pushRegistration = pushRegistration
        self.recipeImage = recipeImage
        self.yjsMergeHelper = yjsMergeHelper

        // Persistent device ID
        if let existing = UserDefaults.standard.string(forKey: "deviceId") {
            self.deviceId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "deviceId")
            self.deviceId = newId
        }

        wireEventHandler()
        markLocalDataLoadedIfTestingHost()
    }

    /// Convenience for previews/tests that only need a YjsSyncService-shaped object
    /// backed by stand-alone service instances. Production code goes through
    /// `AppContainer` which builds the full dependency graph.
    init(store: YDocStore) {
        self.store = store
        self.offlineQueue = OfflineWriteQueue(store: store)
        self.documentManager = DocumentManager(store: store)
        self.eventHandler = SyncEventHandler()
        self.timerSync = TimerSyncService.shared
        self.pushRegistration = PushRegistrationService.shared
        self.recipeImage = RecipeImageService.shared
        self.yjsMergeHelper = YjsMergeHelper.shared

        if let existing = UserDefaults.standard.string(forKey: "deviceId") {
            self.deviceId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "deviceId")
            self.deviceId = newId
        }

        wireEventHandler()
        markLocalDataLoadedIfTestingHost()
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
        await recipeImage.removeCache(recipeId: recipeId)
        if connectionState == .connected {
            let entry = collectionEntry(for: recipeId)
                ?? CollectionEntry(
                    id: recipeId,
                    name: currentRecipe?.name ?? "",
                    color: currentRecipe?.color ?? "#3b82f6",
                    imageUrl: result.imageUrl,
                    updatedAt: ISO8601DateFormatter().string(from: Date()),
                    deleted: false,
                    isPinned: false
                )
            await recipeImage.prefetchPreviews(
                entries: [entry],
                allowNetwork: true
            )
        }
    }

    func applyRecipeImageDeletion(recipeId: String) async throws {
        try await documentManager.clearRecipeImage(recipeId: recipeId)
        await recipeImage.removeCache(recipeId: recipeId)
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
        // 1) WebView debounced Yjs → yrs (waits for apply chain)
        if let bridge = descriptionEditorSessions[recipeId]?.bridge {
            await bridge.flushEditorEdits()
        }
        // 2) Local SQLite snapshot (description editor uses debounced persist)
        await documentManager.flushScheduledSnapshotPersist(docKey: docKeyFor(recipeId: recipeId))
        // 3) Drain debouncer (WebView flush posts yjs encodeStateAsUpdate via syncState)
        let recipeIds = pendingEditRecipeIds()
        for id in recipeIds {
            await updateDebouncer.flushNow(recipeId: id)
        }
        for id in recipeIds {
            await documentManager.persistSnapshot(docKey: docKeyFor(recipeId: id))
        }
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
            let payloads = batch.filter { $0.count > 2 }
            guard !payloads.isEmpty else { continue }
            if payloads.count == 1 {
                await sendDebouncedUpdate(recipeId: recipeId, update: payloads[0])
            } else if let merged = try? await yjsMergeHelper.mergeUpdates(payloads) {
                await sendDebouncedUpdate(recipeId: recipeId, update: merged)
            } else {
                for payload in payloads {
                    await sendDebouncedUpdate(recipeId: recipeId, update: payload)
                }
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
    ///
    /// Every signal here is deterministic: the explicit unsynced flag, the write-sync state, the
    /// durable offline queue, and the in-memory observer. The old `localBytes > serverBytes + 128`
    /// byte-size guess was removed — CRDT byte sizes do not reflect "who is ahead" (a delete can
    /// grow the doc via tombstones), and after a server merge it produced a permanent false
    /// positive that wedged the recipe into skip-pull.
    private func hasUnsyncedLocalChanges(
        recipeId: String,
        queuedRecipeIds: Set<String>? = nil
    ) async -> Bool {
        if unsyncedRecipeIds.contains(recipeId) { return true }
        switch writeSyncStates[recipeId] ?? .idle {
        case .queued, .syncing, .pendingLocal:
            return true
        case .idle, .synced, .error:
            break
        }
        if let queuedRecipeIds {
            if queuedRecipeIds.contains(recipeId) { return true }
        } else if let entries = try? await offlineQueue.fetch(forRecipeId: recipeId),
                  !entries.isEmpty {
            return true
        }
        let pendingObserver = await documentManager.pendingSyncByteCount(recipeId: recipeId)
        if pendingObserver > 0 { return true }
        return false
    }

    /// Deterministic: a recipe is "local-ahead" only when it carries an explicit unsynced flag.
    private func isLocalAheadOfServer(recipeId: String) -> Bool {
        unsyncedRecipeIds.contains(recipeId)
    }

    private func isRecipeDocument(recipeId: String) -> Bool {
        recipeId != "collection" && recipeId != ShoppingListConstants.offlineRecipeId
    }

    /// Web parity: drain durable offline bytes and push full yjs wire state after reconnect.
    func syncPendingDocumentsAfterReconnect(recipeIds: [String]? = nil) async {
        guard userId != nil else { return }
        pendingReconnectSyncTask?.cancel()
        let task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.flushPendingEdits()
            await self.documentManager.applyOfflineQueueToLocalDocs()
            let candidates = recipeIds ?? self.collectionEntries.map(\.id)
            await self.fetchAndMergeServerDocuments(recipeIds: candidates)
            await self.refreshWireSnapshotsForRecipes(recipeIds: candidates)
            await self.drainWhenLiveSyncReady(recipeIds: candidates)
            await self.scheduleDescriptionWireExportIfNeeded(recipeIds: candidates)
            if let active = self.activeRecipeId {
                await self.refreshCurrentRecipeIfAllowed(recipeId: active)
            }
        }
        pendingReconnectSyncTask = task
        await task.value
    }

    private func drainWhenLiveSyncReady(recipeIds: [String]) async {
        let maxAttempts = 50
        for attempt in 0..<maxAttempts {
            if canSendLiveSync() {
                await drainOfflineQueue()
                await pushUnsyncedWireSnapshots(recipeIds: recipeIds)
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Web parity: pull server snapshot and CRDT-merge into local before pushing offline edits.
    private func fetchAndMergeServerDocuments(recipeIds: [String]) async {
        guard canSendLiveSync() else { return }
        let queuedRecipeIds = (try? await offlineQueue.recipeIdsInQueue()) ?? []
        for recipeId in recipeIds where isRecipeDocument(recipeId: recipeId) {
            guard await hasUnsyncedLocalChanges(
                recipeId: recipeId,
                queuedRecipeIds: queuedRecipeIds
            ) else { continue }
            _ = await fetchAndMergeServerDocument(recipeId: recipeId)
        }
    }

    private func fetchAndMergeServerDocument(recipeId: String) async -> Bool {
        guard canSendLiveSync() else { return false }
        if let existingTask = documentLoadTasks[recipeId] {
            return await existingTask.value
        }
        let task = Task { @MainActor in
            let result = await withTaskGroup(of: Bool.self) { group in
                group.addTask { @MainActor in
                    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                        self.documentLoadContinuations[recipeId] = continuation
                        self.socket?.emit("load_document", ["recipeId": recipeId])
                        self.logger.info("Emitted load_document for merge \(recipeId)")
                    }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    return false
                }
                let res = await group.next() ?? false
                group.cancelAll()
                return res
            }
            self.documentLoadTasks.removeValue(forKey: recipeId)
            if !result {
                self.completePendingDocumentLoad(recipeId: recipeId, merged: false)
            }
            return result
        }
        documentLoadTasks[recipeId] = task
        return await task.value
    }

    private func completePendingDocumentLoad(recipeId: String, merged: Bool) {
        documentLoadContinuations.removeValue(forKey: recipeId)?.resume(returning: merged)
        documentLoadTasks.removeValue(forKey: recipeId)
    }

    private func scheduleDescriptionWireExportIfNeeded(recipeIds: [String]) async {
        for recipeId in recipeIds where isRecipeDocument(recipeId: recipeId) {
            guard await hasUnsyncedLocalChanges(recipeId: recipeId) else { continue }
            // A session entry (even with nil bridge) means the editor is in a
            // transition window between deinit and async unregister. Treat it
            // as "session possibly active" and skip the wire export to avoid
            // spurious requests racing with a reopen.
            if descriptionEditorSessions[recipeId] != nil { continue }
            requestDescriptionWireExport(recipeId: recipeId)
        }
    }

    func persistYjsWireSnapshot(recipeId: String, state: Data) async {
        guard isRecipeDocument(recipeId: recipeId), state.count > 2 else { return }
        let docKey = docKeyFor(recipeId: recipeId)
        try? await store.saveYjsWireSnapshot(docKey: docKey, state: state)
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
                        // Сеть ушла — engine/auth watchdog уже не сработает осмысленно
                        // (teardownSocket всё равно разорвёт сессию). Отменяем явно,
                        // чтобы watchdog не поджёг reconnect уже после teardown.
                        self.connectionStepTimer?.cancel()
                        self.connectionStepTimer = nil
                        // На случай, если сеть моргнула дважды — не оставляем висящий debounce.
                        self.networkReconnectDebounceTask?.cancel()
                        self.networkReconnectDebounceTask = nil
                        self.reconcileStuckSyncingStates()
                        Task { await self.flushPendingUpdates(for: self.pendingEditRecipeIds()) }
                        Task { await self.flushPendingEdits() }
                        self.teardownSocket()
                        self.setConnectionState(.disconnected, reason: "network_lost")
                    } else {
                        self.networkReconnectDebounceTask?.cancel()
                        self.networkReconnectDebounceTask = Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            guard let self, !Task.isCancelled, self.isNetworkReachable else { return }
                            self.reconnectAfterNetworkRegained()
                        }
                    }
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.recipescaler.native.network-reachability"))
        networkPathMonitor = monitor
    }

    /// Fresh Socket.IO session after radio returns (web: network online → connect).
    private func reconnectAfterNetworkRegained() {
        guard userId != nil else { return }
        guard !canSendLiveSync() else { return }
        logger.info("Network regained — fresh socket connect")
        connectionTransport = .pollingAndWebsocket
        teardownSocket()
        connectSocket()
    }

    private func reconnectIfNeeded(reason: String) {
        guard userId != nil else { return }
        guard !canSendLiveSync() else { return }
        logger.info("\(reason) — reconnecting socket")
        reconnectAfterNetworkRegained()
    }

    private func stopNetworkMonitor() {
        connectionStepTimer?.cancel()
        connectionStepTimer = nil
        networkReconnectDebounceTask?.cancel()
        networkReconnectDebounceTask = nil
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
    }

    /// Full yjs wire state from WebView flush (`syncState`) — persist, push when online, replace stale queue rows.
    func applyDescriptionSyncState(recipeId: String, state: Data) async {
        guard isRecipeDocument(recipeId: recipeId), state.count > 2 else { return }
        await markRecipeUnsynced(recipeId)
        let docKey = docKeyFor(recipeId: recipeId)
        do {
            try await documentManager.applyDescriptionEditorUpdate(
                recipeId: recipeId,
                update: state,
                forwardToSync: false
            )
        } catch {
            logger.warning("applyDescriptionSyncState apply failed for \(recipeId): \(error)")
            return
        }
        await persistYjsWireSnapshot(recipeId: recipeId, state: state)
        if canSendLiveSync() {
            if let inFlight = inFlightOfflineEntryIdsByDocKey[docKey], !inFlight.isEmpty {
                guard await replaceOfflineQueueForRecipe(
                    docKey: docKey,
                    recipeId: recipeId,
                    canonicalUpdate: state
                ) else { return }
                clearInFlightOfflineTracking(forDocKey: docKey)
            }
            writeSyncStates[recipeId] = .syncing
            await emitSyncRequest(recipeId: recipeId, update: state, docKey: docKey)
        } else {
            writeSyncStates[recipeId] = .queued
            guard await replaceOfflineQueueForRecipe(
                docKey: docKey,
                recipeId: recipeId,
                canonicalUpdate: state
            ) else { return }
            clearInFlightOfflineTracking(forDocKey: docKey)
            await documentManager.persistSnapshot(docKey: docKey)
        }
    }

    func requestDescriptionWireExport(recipeId: String) {
        guard isRecipeDocument(recipeId: recipeId) else { return }
        descriptionWireExportRecipeIds.insert(recipeId)
    }

    func finishDescriptionWireExport(recipeId: String) {
        descriptionWireExportRecipeIds.remove(recipeId)
    }

    func registerDescriptionEditor(_ bridge: DescriptionEditorBridge) {
        pruneStaleDescriptionEditorSessions()
        finishDescriptionWireExport(recipeId: bridge.recipeId)
        let session = DescriptionEditorSession()
        session.bridge = bridge
        descriptionEditorSessions[bridge.recipeId] = session
    }

    func unregisterDescriptionEditor(recipeId: String, bridge: DescriptionEditorBridge) {
        if descriptionEditorSessions[recipeId]?.bridge === bridge {
            descriptionEditorSessions.removeValue(forKey: recipeId)
        }
        pruneStaleDescriptionEditorSessions()
    }

    private func pruneStaleDescriptionEditorSessions() {
        for (recipeId, session) in descriptionEditorSessions {
            if session.bridge == nil {
                descriptionEditorSessions.removeValue(forKey: recipeId)
            }
        }
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

    func updateIngredientIllustrationBinding(
        ingredientId: String,
        illustrationId: String?,
        pickerCleared: Bool
    ) async throws {
        try await updateIngredientIllustrationBindings([
            (ingredientId: ingredientId, illustrationId: illustrationId, pickerCleared: pickerCleared, expectedName: nil),
        ])
    }

    func updateIngredientIllustrationBindings(
        _ bindings: [(ingredientId: String, illustrationId: String?, pickerCleared: Bool, expectedName: String?)]
    ) async throws {
        guard let recipeId = activeRecipeId else { throw RecipeEditError.documentNotLoaded }
        guard !bindings.isEmpty else { return }
        try await documentManager.updateIngredientIllustrationBindings(
            recipeId: recipeId,
            bindings: bindings
        )
        if var recipe = currentRecipe, recipe.id == recipeId {
            var ingredients = recipe.ingredients
            var changed = false
            for binding in bindings {
                guard let index = ingredients.firstIndex(where: { $0.id == binding.ingredientId }) else { continue }
                ingredients[index] = ingredients[index].withIllustrationBinding(
                    illustrationId: binding.illustrationId,
                    pickerCleared: binding.pickerCleared
                )
                changed = true
            }
            if changed {
                recipe = recipe.replacing(ingredients: ingredients)
                currentRecipe = recipe
            }
        }
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
        cancelPendingWork(forRecipeId: recipeId)
        if activeRecipeId == recipeId {
            currentRecipe = nil
            activeRecipeId = nil
            activeRecipeWasRemoved = true
        }
        writeSyncStates.removeValue(forKey: recipeId)
        await markRecipeSynced(recipeId)
        await refreshCollectionEntries()
    }

    /// Creates an empty v3 recipe + collection entry; returns new recipe id.
    func createRecipe() async throws -> String {
        let name = Bundle.currentLocalizedString("recipe.create.new")
        let recipeId = try await documentManager.createRecipe(name: name)
        await refreshCollectionEntries()
        return recipeId
    }

    /// Import a parsed third-party recipe draft into Y.Doc (027).
    func applyImportedRecipe(_ draft: ThirdPartyRecipeDraft) async throws -> String {
        let recipeId = try await documentManager.applyImportedRecipe(draft)
        await refreshCollectionEntries()
        await flushImportSyncBeforeImageUpload(recipeId: recipeId)
        return recipeId
    }

    /// Upload image bytes for a recipe created via third-party import.
    func uploadImportedRecipeImage(recipeId: String, imageData: Data) async throws {
        guard let payload = await RecipeImageUploadPreprocessor.payloadForUpload(from: imageData) else {
            throw ImportedRecipeImageUploadError.preprocessingFailed
        }
        await flushImportSyncBeforeImageUpload(recipeId: recipeId)

        var lastError: Error = ImportedRecipeImageUploadError.preprocessingFailed
        let maxAttempts = 8
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                let delayNs = UInt64(min(attempt, 5)) * 500_000_000
                try await Task.sleep(nanoseconds: delayNs)
                await flushImportSyncBeforeImageUpload(recipeId: recipeId)
            }
            do {
                let result = try await RecipeImageUploadAPI.upload(recipeId: recipeId, payload: payload)
                try await applyRecipeImageUpload(recipeId: recipeId, result: result)
                return
            } catch let error as APIError {
                if case .httpError(let code) = error {
                    if code == 404, attempt < maxAttempts - 1 {
                        lastError = error
                        continue
                    }
                }
                throw error
            }
        }
        throw lastError
    }

    /// Push pending Yjs updates and wait for server ack before `POST /api/recipes/:id/image`
    /// (that endpoint returns 404 until the recipe row exists in Supabase).
    private func flushImportSyncBeforeImageUpload(recipeId: String) async {
        let recipeIds = [recipeId, "collection"]
        for _ in 0..<24 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            await flushPendingUpdates(for: recipeIds)
            let recipePending = await updateDebouncer.hasPending(recipeId: recipeId)
            let collectionPending = await updateDebouncer.hasPending(recipeId: "collection")
            if !recipePending, !collectionPending {
                break
            }
        }
        await waitForRecipeServerAck(recipeId: recipeId, timeoutSeconds: 12)
    }

    private func waitForRecipeServerAck(recipeId: String, timeoutSeconds: Double) async {
        guard canSendLiveSync() else { return }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let state = writeSyncStates[recipeId] ?? .idle
            if state == .synced {
                try? await Task.sleep(nanoseconds: 250_000_000)
                return
            }
            if case .error = state {
                return
            }
            if state == .idle, !unsyncedRecipeIds.contains(recipeId) {
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// US8: assign recipe to folders resolved from Paprika `categories` /
    /// Crouton `tags` labels. Reuses existing folders by case-insensitive
    /// label or creates new ones. Idempotent per (recipeId, label) pair.
    func applyCategoryLabelsToRecipe(recipeId: String, labels: [String]) async throws {
        var folderIds: [String] = []
        for label in labels {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let folderId = try await documentManager.resolveOrCreateFolderId(label: trimmed)
            if !folderIds.contains(folderId) {
                folderIds.append(folderId)
            }
        }
        guard !folderIds.isEmpty else { return }
        try await documentManager.setRecipeFolders(recipeId: recipeId, folderIds: folderIds)
        await refreshCollectionEntries()
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
    ///
    /// Side-effects that previously lived here (configuring `APIClient`,
    /// `TimerSyncService`, `TimerSyncService.sendTimerEvent` callback,
    /// `ImageCacheService` observers, `TimerLiveActivityMetadataProvider`
    /// recipe-name lookup) have been moved to `AppContainer.bootstrap` per
    /// review #27. This keeps `start()` focused on socket + document lifecycle.
    func start(userId: String) async {
        let isSameUser = self.userId == userId
        if !isSameUser, self.userId != nil {
            await documentManager.clearOfflineQueueForAccountSwitch()
            writeSyncStates = [:]
            unsyncedRecipeIds = []
        }
        self.userId = userId
        await migratePlistSyncKeysIfNeeded(userId: userId)
        await loadUnsyncedRecipeIds()
        startNetworkMonitorIfNeeded()
        await documentManager.setUserId(userId)

        // Connect before SQLite snapshot IO so UI is not stuck on "Offline" while docs load.
        beginSocketSession(isSameUser: isSameUser, userId: userId)

        await loadLocalSnapshots()
    }

    /// Re-enter an existing session without re-running first-time wiring.
    /// Called by `AppContainer.bootstrap` when the user has not changed.
    func resumeSession(userId: String) async {
        self.userId = userId
        startNetworkMonitorIfNeeded()
        resumeSocketSession()
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

        logger.info("Starting YjsSync for user \(UserIdFormatter.redact(userId))")
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
            if isNetworkReachable {
                connectSocket()
            }
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
            await syncPendingDocumentsAfterReconnect(recipeIds: [recipeId])
            if await hasUnsyncedLocalChanges(recipeId: recipeId) {
                logger.info("Skipping load_document for \(recipeId) — unsynced local changes")
                return
            }
        }

        socket?.emit("load_document", ["recipeId": recipeId])
        logger.info("Emitted load_document for recipe \(recipeId)")
    }

    /// After `POST /api/v2/recipes/:id/copy`: pull server recipe + collection, ensure
    /// collection metadata has `imageUrl`, and warm on-disk preview cache for the new id.
    func integrateCopiedRecipe(recipeId: String, fallbackImageUrl: String?) async {
        guard userId != nil else { return }
        activeRecipeId = recipeId
        await installChangeHandlersIfNeeded()

        if canSendLiveSync() {
            _ = await fetchAndMergeServerDocument(recipeId: recipeId)
            reloadCollectionFromServer()
        } else {
            await loadRecipe(recipeId: recipeId)
        }

        var resolvedImageUrl: String?
        for attempt in 0 ..< 25 {
            await refreshCollectionEntries()
            if let entry = collectionEntry(for: recipeId),
               let url = entry.imageUrl,
               !url.isEmpty {
                resolvedImageUrl = url
                break
            }
            await refreshCurrentRecipe(recipeId: recipeId)
            if let url = currentRecipe?.imageUrl, !url.isEmpty {
                resolvedImageUrl = url
            }
            if attempt == 0, canSendLiveSync() {
                reloadCollectionFromServer()
            }
            if resolvedImageUrl != nil, collectionEntry(for: recipeId) != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        await syncCollectionImageUrlFromRecipeIfNeeded(recipeId: recipeId)
        await refreshCollectionEntries()
        await refreshCurrentRecipe(recipeId: recipeId)

        let imageUrl = collectionEntry(for: recipeId)?.imageUrl
            ?? currentRecipe?.imageUrl
            ?? fallbackImageUrl
        guard let imageUrl, !imageUrl.isEmpty else { return }
        guard connectionState == .connected else { return }

        let entry = collectionEntry(for: recipeId)
            ?? CollectionEntry(
                id: recipeId,
                name: currentRecipe?.name ?? "",
                color: currentRecipe?.color ?? "#3b82f6",
                imageUrl: imageUrl,
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                deleted: false,
                isPinned: false
            )

        await recipeImage.prefetchPreviews(
            entries: [entry],
            allowNetwork: true
        )
        await refreshImageCacheStatus()
    }

    /// Full local teardown on logout (web: IndexedDB + realtime destroy).
    func clearSessionForLogout() async {
        unsyncedRecipeIds = []
        stop()
        collectionEntries = []
        folders = []
        collectionIndex = .empty
        writeSyncStates = [:]
        imageCacheStatus = RecipeImageCacheStatus()
        await documentManager.resetSession()
        try? await store.deleteAll()
        try? await store.deleteAllOfflineQueue()
        try? await store.deleteAllYjsWireSnapshots()
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

    /// Lightweight search projection without XmlFragment→HTML conversion.
    func peekSearchIndex(recipeId: String) async -> RecipeSearchIndex? {
        guard let userId else { return nil }
        _ = try? await documentManager.getOrCreateDoc(key: docKeyFor(recipeId: recipeId))
        return try? await documentManager.readSearchIndex(recipeId: recipeId, userId: userId)
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
        Task { await flushPendingEdits() }
        teardownSocket()
        setConnectionState(.disconnected, reason: "app_background")
    }

    /// App returned to foreground. Re-establish proactively instead of waiting for the slow,
    /// timeout-driven Socket.IO auto-reconnect (a fresh connect completes in ~0.5s).
    func handleEnteredForeground() {
        guard userId != nil else { return }
        reconnectIfNeeded(reason: "Entered foreground")
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await syncPendingDocumentsAfterReconnect()
        }
    }

    // MARK: - Socket.IO Connection

    private func teardownSocket() {
        clearInFlightOfflineTracking()
        transition(to: .disconnected)
        socket?.disconnect()
        socket = nil
        manager = nil
        isSocketAuthenticated = false
        didEmitAuthThisSession = false
        hasRequestedCollectionLoad = false
        hasRequestedShoppingLoad = false
        cancelAllPendingDocumentLoads()

        for (_, task) in wireSnapshotRefreshTasks {
            task.cancel()
        }
        wireSnapshotRefreshTasks.removeAll()
    }

    private func cancelAllPendingDocumentLoads() {
        for (_, continuation) in documentLoadContinuations {
            continuation.resume(returning: false)
        }
        documentLoadContinuations.removeAll()

        for (_, task) in documentLoadTasks {
            task.cancel()
        }
        documentLoadTasks.removeAll()
    }

    /// MIK-167: cancel and clear every per-recipe dict entry for one recipeId.
    ///
    /// Used when a recipe is deleted — either via a server `sync_error` with
    /// `.recipeDeleted`, or via a local `deleteRecipeFromCollection`. Without
    /// this, mid-load tasks, pending continuations, scheduled wire-snapshot
    /// refreshes, and description-editor sessions stay pinned to the recipeId
    /// until global teardown, leaving zombie entries that violate the
    /// "lifetime tied to owner" contract from MIK-130.
    ///
    /// Order matches `cancelAllPendingDocumentLoads`: resume the continuation
    /// first (so the awaiting TaskGroup completes naturally), then cancel the
    /// wrapping Task, then drop the remaining entries.
    private func cancelPendingWork(forRecipeId recipeId: String) {
        documentLoadContinuations.removeValue(forKey: recipeId)?.resume(returning: false)
        documentLoadTasks.removeValue(forKey: recipeId)?.cancel()
        wireSnapshotRefreshTasks.removeValue(forKey: recipeId)?.cancel()
        descriptionEditorSessions.removeValue(forKey: recipeId)
    }

    private func connectSocket() {
        guard let userId else { return }

        let sessionId = UUID()

        teardownSocket()

        isSocketAuthenticated = false
        didEmitAuthThisSession = false
        hasRequestedCollectionLoad = false
        hasRequestedShoppingLoad = false
        let serverURL = URL(string: Config.baseURL)!
        let deviceToken = SharedAuthStore.token
        var socketConfig: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWait(1000),
            .reconnectWaitMax(5000),
        ]
        if connectionTransport == .websocketOnly {
            socketConfig.insert(.forceWebsockets(true))
        }
        manager = SocketManager(socketURL: serverURL, config: socketConfig)

        let client = manager!.defaultSocket
        self.socket = client
        if let deviceToken, !deviceToken.isEmpty {
            client.connect(withPayload: ["token": deviceToken])
        } else {
            client.connect()
        }

        // Socket lifecycle handlers
        client.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                self.logger.info("Socket.IO connected")
                self.setConnectionState(.connecting, reason: "socket.connect")
                self.isSocketAuthenticated = false
                self.transition(to: .authenticating(sessionId: sessionId))
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
                // Server may ack multiple times if it received multiple `auth`
                // emits (e.g. transport upgrade races). Only the first ack should
                // drive the state machine; subsequent ones are no-ops.
                guard !self.isSocketAuthenticated else { return }
                self.logger.info("Socket.IO authenticated (server ack)")
                self.markAuthenticatedAndLoadCollection(sessionId: sessionId)
            }
        }

        client.on("timer_event") { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                guard let payload = data.first as? [String: Any] else { return }
                self.timerSync.handleWebSocketPayload(payload)
            }
        }

        client.on("auth_error") { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionId) else { return }
                let message = data.first as? [String: Any]
                let detail = message?["message"] as? String ?? "Authentication failed"
                // Log the raw server detail for diagnostics, but never route it to the UI —
                // a compromised server or MITM could otherwise inject arbitrary text into
                // the trusted sync banner (`ConnectionState.displayLabel`). MIK-163.
                self.logger.error("Socket.IO auth_error: \(detail)")
                let userMessage = Bundle.currentLocalizedString("connection.state.auth-error")
                self.setConnectionState(.error(userMessage), reason: "auth_error")
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
                self.didEmitAuthThisSession = false
                self.hasRequestedCollectionLoad = false
                self.hasRequestedShoppingLoad = false
                self.transition(to: .disconnected)
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
                self.didEmitAuthThisSession = false
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
                self.didEmitAuthThisSession = false
                self.hasRequestedCollectionLoad = false
                self.hasRequestedShoppingLoad = false
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
        setConnectionState(.connecting, reason: "connect_socket_called")
        transition(to: .connecting(sessionId: sessionId))
    }

    private func isCurrentSocketSession(_ sessionId: UUID) -> Bool {
        switch connectionStep {
        case .disconnected:
            return false
        case .connecting(let id), .authenticating(let id), .authenticated(let id):
            return id == sessionId
        }
    }

    private func transition(to step: ConnectionStep) {
        connectionStepTimer?.cancel()
        connectionStepTimer = nil

        connectionStep = step

        switch step {
        case .disconnected:
            break

        case .connecting(let sessionId):
            connectionStepTimer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    self.handleStuckEngineConnect(sessionId: sessionId, trigger: "engine_connect_timeout")
                }
            }

        case .authenticating(let sessionId):
            connectionStepTimer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    if self.isSocketAuthenticated { return }
                    guard self.socket?.status == .connected else { return }
                    self.logger.warning("Socket auth ack timeout; loading collection after delay")
                    self.markAuthenticatedAndLoadCollection(sessionId: sessionId)
                }
            }

        case .authenticated:
            break
        }
    }

    private func setConnectionState(_ state: ConnectionState, reason: String) {
        connectionState = state
        if !state.isConnected {
            reconcileStuckSyncingStates()
        }
        _ = reason
    }

    private func emitAuth() {
        if let token = SharedAuthStore.token, !token.isEmpty {
            return
        }
        guard let userId else { return }
        guard let sessionAtEmit = socketSessionId else { return }

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
        guard !didEmitAuthThisSession else {
            // Auth already emitted in this socket session — server ack is pending
            // or has arrived. Emitting again would produce a duplicate ack and
            // re-trigger markAuthenticatedAndLoadCollection.
            return true
        }
        didEmitAuthThisSession = true
        socket.emit("auth", [
            "userId": userId,
            "deviceId": deviceId,
        ])
        logger.info("Emitted auth for user \(UserIdFormatter.redact(userId))")
        return true
    }

    private func handleStuckEngineConnect(sessionId: UUID, trigger: String) {
        guard isCurrentSocketSession(sessionId) else { return }
        guard !isSocketAuthenticated else { return }
        guard socket?.status != .connected else {
            transition(to: .authenticating(sessionId: sessionId))
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

    private func markAuthenticatedAndLoadCollection(sessionId: UUID) {
        transition(to: .authenticated(sessionId: sessionId))
        isSocketAuthenticated = true
        setConnectionState(.connected, reason: "authenticated")
        if disconnectTimestamp != nil {
            Task {
                await syncPendingDocumentsAfterReconnect()
                reloadStaleDocumentsAfterReconnect()
            }
        } else {
            loadCollectionDocument()
            Task { await syncPendingDocumentsAfterReconnect() }
        }
        timerSync.initializeAfterAuth()
        Task { await pushRegistration.registerIfNeeded() }
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

        eventHandler.onSyncError = { [weak self] code, message, recipeId in
            Task { @MainActor in
                await self?.handleSyncError(code: code, message: message, recipeId: recipeId)
            }
        }

        eventHandler.onSyncConfirmed = { [weak self] recipeId, lastSyncedAt in
            Task { @MainActor in
                await self?.handleSyncConfirmed(recipeId: recipeId, lastSyncedAt: lastSyncedAt)
            }
        }
    }

    private func handleLocalRecipeUpdate(recipeId: String, update: Data) async {
        await markRecipeUnsynced(recipeId)
        writeSyncStates[recipeId] = .pendingLocal
        await updateDebouncer.schedule(recipeId: recipeId, update: update)
    }

    private func handleDescriptionYjsUpdate(recipeId: String, update: Data) async {
        guard !update.isEmpty, update.count > 2 else { return }
        await markRecipeUnsynced(recipeId)
        writeSyncStates[recipeId] = .pendingLocal
        let docKey = docKeyFor(recipeId: recipeId)
        if !canSendLiveSync() {
            writeSyncStates[recipeId] = .queued
            try? await offlineQueue.enqueue(docKey: docKey, recipeId: recipeId, yjsUpdate: update)
            await documentManager.persistSnapshot(docKey: docKey)
            scheduleWireSnapshotRefresh(recipeId: recipeId)
            logger.info("Eager offline enqueue for description \(recipeId) (\(update.count) bytes)")
            return
        }
        await updateDebouncer.schedule(recipeId: recipeId, update: update)
    }

    private func scheduleWireSnapshotRefresh(recipeId: String) {
        wireSnapshotRefreshTasks[recipeId]?.cancel()
        wireSnapshotRefreshTasks[recipeId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self else { return }
            if !Task.isCancelled {
                await self.refreshWireSnapshotForRecipe(recipeId: recipeId)
            }
            self.wireSnapshotRefreshTasks.removeValue(forKey: recipeId)
        }
    }

    private func refreshWireSnapshotsForRecipes(recipeIds: [String]) async {
        let candidates = recipeIds.filter { isRecipeDocument(recipeId: $0) }
        guard !candidates.isEmpty else { return }
        let queuedRecipeIds = (try? await offlineQueue.recipeIdsInQueue()) ?? []
        let docKeys = candidates.map { docKeyFor(recipeId: $0) }
        let wireSnapshots = (try? await store.loadYjsWireSnapshots(docKeys: docKeys)) ?? [:]
        let snapshots = (try? await store.loadSnapshots(docKeys: docKeys)) ?? [:]
        let allQueue = (try? await offlineQueue.fetchAll()) ?? []
        var queueByRecipeId: [String: [OfflineSyncEntry]] = [:]
        for entry in allQueue {
            queueByRecipeId[entry.recipeId, default: []].append(entry)
        }
        for recipeId in candidates {
            guard await hasUnsyncedLocalChanges(
                recipeId: recipeId,
                queuedRecipeIds: queuedRecipeIds
            ) else { continue }
            let docKey = docKeyFor(recipeId: recipeId)
            await refreshWireSnapshotForRecipe(
                recipeId: recipeId,
                wireSnapshot: wireSnapshots[docKey],
                snapshot: snapshots[docKey],
                queueEntries: queueByRecipeId[recipeId] ?? []
            )
        }
    }

    /// Rebuild durable yjs wire bytes from wire/yrs bootstrap + queued incrementals (never stale wire alone).
    private func refreshWireSnapshotForRecipe(
        recipeId: String,
        wireSnapshot: YjsWireSnapshot? = nil,
        snapshot: YDocSnapshot? = nil,
        queueEntries: [OfflineSyncEntry]? = nil
    ) async {
        let docKey = docKeyFor(recipeId: recipeId)
        let resolvedQueueEntries: [OfflineSyncEntry]
        if let queueEntries {
            resolvedQueueEntries = queueEntries
        } else {
            // Debounced single-recipe path: SQL filter, not full-queue scan (MIK-173).
            resolvedQueueEntries = (try? await offlineQueue.fetch(forRecipeId: recipeId)) ?? []
        }
        let parts = resolvedQueueEntries.map(\.yjsUpdate).filter { $0.count > 2 }
        let wireBootstrap: Data?
        if let state = wireSnapshot?.state {
            wireBootstrap = state
        } else {
            wireBootstrap = try? await store.loadYjsWireSnapshot(docKey: docKey)?.state
        }
        let yrsBootstrap: Data?
        if let state = snapshot?.state {
            yrsBootstrap = state
        } else {
            yrsBootstrap = try? await store.loadSnapshot(docKey: docKey)?.state
        }
        guard let bootstrap = wireBootstrap ?? yrsBootstrap, bootstrap.count > 2 else {
            return
        }
        let updates = parts
        guard let full = try? await yjsMergeHelper.encodeFullState(
            bootstrap: bootstrap,
            updates: updates
        ), full.count > 2 else {
            return
        }
        try? await store.saveYjsWireSnapshot(docKey: docKey, state: full)
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

    @discardableResult
    private func emitSyncRequest(
        recipeId: String,
        update: Data,
        docKey: String,
        documentKind: String? = nil
    ) async -> Bool {
        guard socket?.status == .connected, isSocketAuthenticated else { return false }
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
        return true
    }

    private func handleSyncConfirmed(recipeId: String, lastSyncedAt: String?) async {
        guard recipeId != "unknown" else { return }
        let docKey = docKeyFor(recipeId: recipeId)
        await acknowledgeOfflineBatch(docKey: docKey)
        lastSuccessfulSyncAt = Date()

        if let doc = await documentManager.getDoc(key: docKey),
           let state = await doc.encodeStateAsUpdate() {
            try? await store.saveSnapshot(docKey: docKey, state: state, lastSyncedAt: lastSyncedAt)
        }

        if isRecipeDocument(recipeId: recipeId) {
            try? await store.deleteYjsWireSnapshot(docKey: docKey)
        }

        if isRecipeDocument(recipeId: recipeId) {
            let stillQueued = !((try? await offlineQueue.fetch(forRecipeId: recipeId)) ?? []).isEmpty
            if stillQueued {
                await markRecipeUnsynced(recipeId)
                writeSyncStates[recipeId] = .queued
            } else {
                await markRecipeSynced(recipeId)
                writeSyncStates[recipeId] = .synced
            }
        }
    }

    private func drainOfflineQueue() async {
        guard canSendLiveSync() else { return }
        guard let entries = try? await offlineQueue.fetchAll(), !entries.isEmpty else { return }

        expireInFlightOfflineBatchesIfNeeded()

        var byDocKey: [String: [OfflineSyncEntry]] = [:]
        for entry in entries {
            byDocKey[entry.docKey, default: []].append(entry)
        }

        for (docKey, docEntries) in byDocKey {
            if let inFlight = inFlightOfflineEntryIdsByDocKey[docKey], !inFlight.isEmpty {
                AppLog.info(.sync, "offline_drain_skip_in_flight", data: [
                    "docKey": docKey,
                    "inFlightCount": String(inFlight.count),
                ])
                continue
            }
            guard let recipeId = docEntries.first?.recipeId else { continue }
            let pushData: Data?
            if isRecipeDocument(recipeId: recipeId) {
                pushData = await resolveYjsPushPayload(
                    recipeId: recipeId,
                    docKey: docKey,
                    queueEntries: docEntries
                )
            } else {
                pushData = await resolveNonRecipePushPayload(docKey: docKey, queueEntries: docEntries)
            }
            guard let pushData, pushData.count > 2 else { continue }
            let documentKind = recipeId == ShoppingListConstants.offlineRecipeId
                ? ShoppingListConstants.documentKind
                : nil
            if recipeId != ShoppingListConstants.offlineRecipeId {
                writeSyncStates[recipeId] = .syncing
            }
            let emitted = await emitSyncRequest(
                recipeId: recipeId,
                update: pushData,
                docKey: docKey,
                documentKind: documentKind
            )
            if emitted {
                let ids = Set(docEntries.compactMap(\.id))
                inFlightOfflineEntryIdsByDocKey[docKey] = ids
                inFlightOfflineStartedAtByDocKey[docKey] = Date()
                AppLog.info(.sync, "offline_drain_in_flight", data: [
                    "docKey": docKey,
                    "recipeId": recipeId,
                    "entryCount": String(ids.count),
                ])
            }
        }
        logger.info("Drained offline sync queue (\(entries.count) entries)")
    }

    private func pushUnsyncedWireSnapshots(recipeIds: [String]) async {
        guard canSendLiveSync() else { return }
        let queued = (try? await offlineQueue.fetchAll()) ?? []
        let queuedRecipeIds = Set(queued.map(\.recipeId))
        for recipeId in recipeIds {
            guard isRecipeDocument(recipeId: recipeId) else { continue }
            guard await hasUnsyncedLocalChanges(
                recipeId: recipeId,
                queuedRecipeIds: queuedRecipeIds
            ) else { continue }
            let docKey = docKeyFor(recipeId: recipeId)
            let queueEntries = queued.filter { $0.recipeId == recipeId }
            if !queueEntries.isEmpty { continue }
            guard let pushData = await resolveYjsPushPayload(
                recipeId: recipeId,
                docKey: docKey,
                queueEntries: []
            ), pushData.count > 2 else { continue }
            writeSyncStates[recipeId] = .syncing
            await emitSyncRequest(recipeId: recipeId, update: pushData, docKey: docKey)
        }
    }

    private func resolveYjsPushPayload(
        recipeId: String,
        docKey: String,
        queueEntries: [OfflineSyncEntry]
    ) async -> Data? {
        let parts = queueEntries.map(\.yjsUpdate).filter { $0.count > 2 }
        let wireBootstrap = try? await store.loadYjsWireSnapshot(docKey: docKey)?.state
        let yrsBootstrap = try? await store.loadSnapshot(docKey: docKey)?.state
        let bootstrap = wireBootstrap ?? yrsBootstrap

        if !parts.isEmpty, let bootstrap {
            if let full = try? await yjsMergeHelper.encodeFullState(
                bootstrap: bootstrap,
                updates: parts
            ), full.count > 2 {
                return full
            }
            if parts.count == 1 { return parts[0] }
            if let merged = try? await yjsMergeHelper.mergeUpdates(parts) { return merged }
            return parts.last
        }

        if let wire = wireBootstrap, wire.count > 2, isLocalAheadOfServer(recipeId: recipeId) {
            return wire
        }

        if isLocalAheadOfServer(recipeId: recipeId),
           let bootstrap,
           let full = try? await yjsMergeHelper.encodeFullState(bootstrap: bootstrap, updates: []),
           full.count > 2 {
            return full
        }
        return nil
    }

    private func resolveNonRecipePushPayload(
        docKey: String,
        queueEntries: [OfflineSyncEntry]
    ) async -> Data? {
        if queueEntries.count == 1 {
            return queueEntries[0].yjsUpdate
        }
        if let doc = await documentManager.getDoc(key: docKey),
           let snapshot = await doc.encodeStateAsUpdate() {
            return snapshot
        }
        return queueEntries.last?.yjsUpdate
    }

    // MARK: - Event Handlers

    /// Web parity: merge server snapshot into local doc when local state exists; replace only when empty.
    private func applyServerDocumentState(
        recipeId: String,
        docKey: String,
        stateData: Data,
        lastSyncedAt: String?
    ) async throws {
        // Web parity: CRDT-merge server state into local even when outbound queue is non-empty.
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
            logger.info("Merged server document into \(UserIdFormatter.redactDocKey(docKey)) (\(stateData.count) bytes)")
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
        logger.info("document_loaded: \(UserIdFormatter.redactDocKey(docKey)), \(stateData.count) bytes")
        lastSuccessfulSyncAt = Date()

        var mergeSucceeded = false
        do {
            try await applyServerDocumentState(
                recipeId: recipeId,
                docKey: docKey,
                stateData: stateData,
                lastSyncedAt: lastSyncedAt
            )
            mergeSucceeded = true
        } catch {
            logger.error("Failed to apply document state for \(UserIdFormatter.redactDocKey(docKey)): \(error)")
        }

        if isRecipeDocument(recipeId: recipeId) {
            if mergeSucceeded {
                descriptionEditorSessions[recipeId]?.bridge?.applyRemoteUpdate(stateData)
            }
            completePendingDocumentLoad(recipeId: recipeId, merged: mergeSucceeded)
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
                logger.error("Failed to apply batch doc \(UserIdFormatter.redactDocKey(docKey)): \(error)")
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
        }
        recipeBatchLoadInFlight = false
        recipeBatchLoadTotal = 0
        recipeBatchLoadCompleted = 0
        await refreshRecipeDocumentCacheStatus()
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
        guard userId != nil else { return [] }
        let candidates = recipeIds.filter { isRecipeDocument(recipeId: $0) }
        let docKeys = candidates.map { docKeyFor(recipeId: $0) }
        guard !docKeys.isEmpty else { return [] }
        let existing = (try? await store.existingSnapshotKeys(docKeys: docKeys)) ?? []
        return zip(candidates, docKeys)
            .compactMap { recipeId, docKey in existing.contains(docKey) ? nil : recipeId }
    }

    private func handleRecipeUpdated(recipeId: String, updateData: Data) async {
        let docKey = docKeyFor(recipeId: recipeId)
        logger.debug("recipe_updated: \(UserIdFormatter.redactDocKey(docKey)), \(updateData.count) bytes")
        lastSuccessfulSyncAt = Date()

        let suppressObserver = recipeRefreshSuspended > 0 && activeRecipeId == recipeId
        do {
            try await documentManager.applyUpdate(
                key: docKey,
                data: updateData,
                suppressRecipeChangeNotification: suppressObserver
            )
        } catch {
            logger.error("Failed to apply recipe update for \(UserIdFormatter.redactDocKey(docKey)): \(error)")
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

    // MARK: - Native Export/Import (029)

    /// Public read for export: reads a single recipe's full data from Y.Doc.
    func readRecipeData(recipeId: String) async throws -> RecipeData? {
        guard let userId else { return nil }
        return try await documentManager.readRecipeData(recipeId: recipeId, userId: userId)
    }

    /// Apply a native-format recipe draft to Y.Doc (029).
    /// Full-field write: preserves color, servings, nutrition, dates, originalRecipe/Link.
    func applyNativeRecipe(_ draft: NativeRecipe) async throws -> String {
        let recipeId = try await documentManager.applyNativeRecipe(draft)
        await refreshCollectionEntries()
        await flushImportSyncBeforeImageUpload(recipeId: recipeId)
        return recipeId
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
        guard userId != nil else {
            recipeDocumentCacheStatus = RecipeDocumentCacheStatus()
            return
        }
        let entries = collectionEntries
        let docKeys = entries.map { docKeyFor(recipeId: $0.id) }
        let existingKeys = (try? await store.existingSnapshotKeys(docKeys: docKeys)) ?? []
        var cached = 0
        var pending: [RecipeDocumentCachePendingEntry] = []
        for entry in entries {
            let key = docKeyFor(recipeId: entry.id)
            if existingKeys.contains(key) {
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
        let status = await recipeImage.cacheStatus(for: collectionEntries)
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

    func installImageCacheObserversIfNeeded() {
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
            await recipeImage.prefetchPreviews(
                entries: entries,
                allowNetwork: allowNetwork
            )
            await refreshImageCacheStatus()
        }
    }

    // MARK: - Collection Reading

    private func scheduleCollectionEntriesRefresh() {
        collectionEntriesRefreshTask?.cancel()
        collectionEntriesRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshCollectionEntries()
        }
    }

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
            // Idempotent: skip reassignment when the value is unchanged so we
            // don't trigger an extra render pass on every observer / echo.
            // This collapses the three refresh paths (setRecipePinned,
            // debounced observer, server echo) into one visual update when
            // they all produce the same entries.
            if collectionEntries != filtered {
                collectionEntries = filtered
            }
            // Idempotent: skip reassignment when the derived index is unchanged so
            // observers (list / collections root) do not re-render on echo refreshes.
            let newIndex = CollectionRecipesIndexBuilder.build(from: filtered)
            if collectionIndex != newIndex {
                collectionIndex = newIndex
            }
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
            if folders != active {
                folders = active
            }
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

    /// Under XCTest/UI-test hosts `AppContainer.bootstrap` never loads local snapshots,
    /// so collection views would spin forever on `isLocalDataLoaded == false`. Mark ready
    /// at construction time for those hosts only.
    private func markLocalDataLoadedIfTestingHost() {
        let isTestingHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("ui-testing")
        if isTestingHost {
            isLocalDataLoaded = true
        }
    }

    private func installChangeHandlersIfNeeded() async {
        if !localUpdateHandlerInstalled {
            localUpdateHandlerInstalled = true
            await documentManager.setLocalUpdateHandler { [weak self] recipeId, update in
                await self?.handleLocalRecipeUpdate(recipeId: recipeId, update: update)
            }
            await documentManager.setDescriptionYjsUpdateHandler { [weak self] recipeId, update in
                await self?.handleDescriptionYjsUpdate(recipeId: recipeId, update: update)
            }
        }
        guard !changeHandlersInstalled else { return }
        changeHandlersInstalled = true
        await documentManager.setChangeHandlers(
            onCollectionChanged: { [weak self] in
                Task { @MainActor in
                    self?.scheduleCollectionEntriesRefresh()
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

    private func handleSyncError(code: SyncErrorCode, message: String, recipeId: String?) async {
        logger.error("Sync error: \(AppLog.sanitizeForLog(message)), code: \(code.rawValue), recipeId: \(UserIdFormatter.redactRecipeId(recipeId))")

        if let recipeId, recipeId != "collection" {
            writeSyncStates[recipeId] = .error(code.localizedMessage)
            if activeRecipeId == recipeId {
                syncErrorMessage = code.localizedMessage
            }
        }

        switch code {
        case .ownershipFailed:
            setConnectionState(.error(code.localizedMessage), reason: "sync_error_ownership")
            if let recipeId {
                clearInFlightOfflineTracking(forDocKey: docKeyFor(recipeId: recipeId))
            }

        case .recipeDeleted:
            guard let recipeId else { return }
            cancelPendingWork(forRecipeId: recipeId)
            if activeRecipeId == recipeId {
                currentRecipe = nil
                activeRecipeId = nil
                activeRecipeWasRemoved = true
            }
            clearInFlightOfflineTracking(forDocKey: docKeyFor(recipeId: recipeId))
            try? await offlineQueue.clear(forRecipeId: recipeId)
            writeSyncStates.removeValue(forKey: recipeId)
            await markRecipeSynced(recipeId)
            await refreshCollectionEntries()

        case .emptyUpdate, .invalidUpdate:
            if let recipeId {
                clearInFlightOfflineTracking(forDocKey: docKeyFor(recipeId: recipeId))
                requestDocumentReload(recipeId: recipeId)
            } else {
                hasRequestedCollectionLoad = false
                loadCollectionDocument()
            }

        case .generic:
            guard let recipeId else { return }
            let docKey = docKeyFor(recipeId: recipeId)
            Task.detached { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    self.clearInFlightOfflineTracking(forDocKey: docKey)
                    self.requestDocumentReload(recipeId: recipeId)
                }
            }
        }
    }

    private func requestDocumentReload(recipeId: String) {
        guard socket?.status == .connected, isSocketAuthenticated else { return }
        if recipeId == "collection" {
            reloadCollectionFromServer()
        } else {
            socket?.emit("load_document", ["recipeId": recipeId])
        }
    }

    private func reloadCollectionFromServer() {
        guard socket?.status == .connected, isSocketAuthenticated else { return }
        hasRequestedCollectionLoad = false
        loadCollectionDocument()
    }

    private func syncCollectionImageUrlFromRecipeIfNeeded(recipeId: String) async {
        guard let entry = collectionEntry(for: recipeId),
              entry.imageUrl?.isEmpty != false else { return }
        guard let userId else { return }
        guard let recipe = try? await documentManager.readRecipeData(recipeId: recipeId, userId: userId),
              let imageUrl = recipe.imageUrl,
              !imageUrl.isEmpty else { return }

        let touchedAt = ISO8601DateFormatter().string(from: Date())
        try? await documentManager.updateCollectionEntry(recipeId: recipeId, touchedAt: touchedAt) { writer in
            writer.setImageUrl(imageUrl)
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
        logger.info("Reload requested after reconnect for \(UserIdFormatter.redactDocKey(collectionKey))")
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

    private func clearInFlightOfflineTracking(forDocKey docKey: String? = nil) {
        if let docKey {
            inFlightOfflineEntryIdsByDocKey.removeValue(forKey: docKey)
            inFlightOfflineStartedAtByDocKey.removeValue(forKey: docKey)
        } else {
            inFlightOfflineEntryIdsByDocKey.removeAll()
            inFlightOfflineStartedAtByDocKey.removeAll()
        }
    }

    /// Clears in-flight tracking for batches older than `offlineInFlightTimeout` so drain can retry.
    private func expireInFlightOfflineBatchesIfNeeded() {
        let now = Date()
        for docKey in Array(inFlightOfflineEntryIdsByDocKey.keys) {
            guard let started = inFlightOfflineStartedAtByDocKey[docKey] else {
                inFlightOfflineStartedAtByDocKey[docKey] = now
                continue
            }
            guard now.timeIntervalSince(started) >= Self.offlineInFlightTimeout else { continue }
            let count = inFlightOfflineEntryIdsByDocKey[docKey]?.count ?? 0
            clearInFlightOfflineTracking(forDocKey: docKey)
            AppLog.info(.sync, "offline_in_flight_timeout", data: [
                "docKey": docKey,
                "inFlightCount": String(count),
            ])
        }
    }

    /// Replaces queued rows for one recipe doc; surfaces persistence failures on recipe write sync state.
    @discardableResult
    private func replaceOfflineQueueForRecipe(
        docKey: String,
        recipeId: String,
        canonicalUpdate: Data
    ) async -> Bool {
        do {
            try await offlineQueue.replaceForRecipe(
                docKey: docKey,
                recipeId: recipeId,
                canonicalUpdate: canonicalUpdate
            )
            return true
        } catch {
            AppLog.info(.sync, "offline_queue_replace_failed", data: [
                "docKey": docKey,
                "recipeId": recipeId,
                "error": String(describing: error),
            ])
            if isRecipeDocument(recipeId: recipeId) {
                writeSyncStates[recipeId] = .error(UserFacingAPIError.message(for: error))
            }
            return false
        }
    }

    private func acknowledgeOfflineBatch(docKey: String) async {
        let pending = inFlightOfflineEntryIdsByDocKey.removeValue(forKey: docKey) ?? []
        guard !pending.isEmpty else {
            inFlightOfflineStartedAtByDocKey.removeValue(forKey: docKey)
            return
        }
        do {
            try await offlineQueue.deleteEntries(ids: Array(pending))
            inFlightOfflineStartedAtByDocKey.removeValue(forKey: docKey)
            AppLog.info(.sync, "offline_batch_acknowledged", data: [
                "docKey": docKey,
                "deletedCount": String(pending.count),
            ])
        } catch {
            inFlightOfflineEntryIdsByDocKey[docKey] = pending
            if inFlightOfflineStartedAtByDocKey[docKey] == nil {
                inFlightOfflineStartedAtByDocKey[docKey] = Date()
            }
            AppLog.info(.sync, "offline_batch_ack_delete_failed", data: [
                "docKey": docKey,
                "error": String(describing: error),
            ])
        }
    }
}

#if DEBUG
extension YjsSyncService {
    var test_documentLoadContinuationsCount: Int { documentLoadContinuations.count }
    var test_documentLoadTasksCount: Int { documentLoadTasks.count }
    var test_descriptionEditorSessionsCount: Int { descriptionEditorSessions.count }
    var test_wireSnapshotRefreshTasksCount: Int { wireSnapshotRefreshTasks.count }

    func test_simulateLoadDocument(recipeId: String, continuation: CheckedContinuation<Bool, Never>) {
        documentLoadContinuations[recipeId] = continuation
    }

    func test_simulateLoadTask(recipeId: String, task: Task<Bool, Never>) {
        documentLoadTasks[recipeId] = task
    }

    func test_simulateWireSnapshotRefreshTask(recipeId: String, task: Task<Void, Never>) {
        wireSnapshotRefreshTasks[recipeId] = task
    }

    func test_simulateAddSession(recipeId: String, session: DescriptionEditorSession) {
        descriptionEditorSessions[recipeId] = session
    }

    func test_cancelPendingWork(forRecipeId recipeId: String) {
        cancelPendingWork(forRecipeId: recipeId)
    }

    func test_pruneSessions() {
        pruneStaleDescriptionEditorSessions()
    }

    func test_descriptionEditorSessionBridge(for recipeId: String) -> DescriptionEditorBridge? {
        descriptionEditorSessions[recipeId]?.bridge
    }

    func test_drainOfflineQueue() async {
        await drainOfflineQueue()
    }

    func test_handleSyncConfirmed(recipeId: String, lastSyncedAt: String?) async {
        await handleSyncConfirmed(recipeId: recipeId, lastSyncedAt: lastSyncedAt)
    }

    func test_inFlightEntryIds(forDocKey docKey: String) -> Set<Int64> {
        inFlightOfflineEntryIdsByDocKey[docKey] ?? []
    }

    func test_clearInFlightOfflineTracking() {
        clearInFlightOfflineTracking()
    }

    func test_docKeyFor(recipeId: String) -> String {
        docKeyFor(recipeId: recipeId)
    }

    var test_offlineQueue: OfflineWriteQueue { offlineQueue }

    func test_setUserIdForOfflineTests(_ userId: String) async {
        self.userId = userId
        await documentManager.setUserId(userId)
    }

    func test_markInFlightForTests(docKey: String, entryIds: Set<Int64>) {
        inFlightOfflineEntryIdsByDocKey[docKey] = entryIds
        inFlightOfflineStartedAtByDocKey[docKey] = Date()
    }

    func test_setInFlightStartedAtForTests(docKey: String, startedAt: Date) {
        inFlightOfflineStartedAtByDocKey[docKey] = startedAt
    }

    func test_expireInFlightOfflineBatchesIfNeeded() {
        expireInFlightOfflineBatchesIfNeeded()
    }

    func test_clearInFlight(forDocKey docKey: String) {
        clearInFlightOfflineTracking(forDocKey: docKey)
    }

    func test_recipeHasQueuedWork(recipeId: String) -> Bool {
        unsyncedRecipeIds.contains(recipeId) || writeSyncStates[recipeId] == .queued
    }

    /// Mirrors offline tail of `applyDescriptionSyncState` (replace + clear in-flight).
    func test_offlineReplaceQueueAndClearInFlight(
        docKey: String,
        recipeId: String,
        canonicalUpdate: Data
    ) async throws {
        try await offlineQueue.replaceForRecipe(
            docKey: docKey,
            recipeId: recipeId,
            canonicalUpdate: canonicalUpdate
        )
        clearInFlightOfflineTracking(forDocKey: docKey)
    }
}
#endif
