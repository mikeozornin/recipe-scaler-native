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
    /// Polling-first: direct WebSocket (`forceWebsockets`) hangs ~8s on Starscream
    /// then falls back anyway. Upgrade to WS still attempted after polling handshake.
    private(set) var connectionTransport: SyncConnectionTransport = .pollingAndWebsocket
    private(set) var writeSyncStates: [String: WriteSyncState] = [:]
    var syncErrorMessage: String?

    /// Spec 055 Phase R: callback invoked when the socket receives an
    /// `auth_error` whose `message` matches
    /// `AuthRevocationConstants.accountDeletedSocketMessage` — the server's
    /// post-commit teardown signal for account deletion (online peer path).
    ///
    /// Set by `AppContainer.init` to delegate into
    /// `AuthService.handleAccountDeleted(reason: .socketSignal)`. `nil` by
    /// default so previews/tests without a container simply no-op.
    var authInvalidationHandler: ((AccountInvalidationReason) async -> Void)?

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
        case connecting(context: SyncSocketSessionContext)
        case authenticating(context: SyncSocketSessionContext)
        case authenticated(context: SyncSocketSessionContext)
    }

    private enum CollectionHandshakeState: Equatable {
        case idle
        case handshaking
        case recovering
        case ready
    }

    private enum SyncSessionError: Error {
        case stale
    }

    private var connectionStep: ConnectionStep = .disconnected
    /// FSM watchdog: engine-connect timeout (8s) или auth-ack timeout (2s).
    /// Единственный владелец — `transition(to:)`. Не использовать вне переходов
    /// FSM-step — иначе network-debounce отменяет watchdog при сетевом мерцании
    /// (регрессия, описанная в MIK-161).
    private var connectionStepTimer: Task<Void, Never>?
    private var authRetryTask: Task<Void, Never>?
    /// Serializes `sync_update` emits so Socket.IO polling does not batch multiple
    /// large binary payloads (+ sync_step1) into one HTTP POST that fails with
    /// `Error flushing waiting posts`.
    private var syncEmitTail: Task<Bool, Never>?
    private var syncEmitTasks: [UUID: Task<Bool, Never>] = [:]
    private var socketSessionId: UUID? {
        switch connectionStep {
        case .disconnected:
            return nil
        case .connecting(let context), .authenticating(let context), .authenticated(let context):
            return context.sessionId
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
    private var collectionHandshakeState: CollectionHandshakeState = .idle
    private var collectionHandshakeContext: SyncSocketSessionContext?
    /// Per-request `sync_step1` probe timers. If `sync_step2` does not arrive
    /// within the window, fall back once to legacy `load_document` (web parity).
    /// Intentionally **not** pinned forever to legacy — the next load retries
    /// the new protocol first.
    private var pendingSyncStep1Probes: [String: (context: SyncSocketSessionContext, task: Task<Void, Never>)] = [:]
    private static let syncStep1ProbeWindowNs: UInt64 = 5_000_000_000
    private var recipeBatchLoadTask: Task<Void, Never>?
    private var recipeBatchLoadInFlight = false
    private var recipeBatchLoadCompleted = 0
    private var recipeBatchLoadTotal = 0

    private var activeRecipeId: String?
    private var disconnectTimestamp: Date?
    private var pendingReconnectSyncTask: Task<Void, Never>?
    private var delayedReconnectSyncTask: Task<Void, Never>?
    private var delayedSyncErrorTask: Task<Void, Never>?
    private var changeHandlersInstalled = false
    private var localUpdateHandlerInstalled = false
    private var recipeRefreshSuspended = 0
    @ObservationIgnored private var _updateDebouncer: UpdateDebouncer?
    private var updateDebouncer: UpdateDebouncer {
        if let _updateDebouncer {
            return _updateDebouncer
        }
        let d = UpdateDebouncer { [weak self] userId, recipeId, update in
            await self?.sendDebouncedUpdate(userId: userId, recipeId: recipeId, update: update)
        }
        _updateDebouncer = d
        return d
    }
    private var imageCacheStatusRefreshTask: Task<Void, Never>?
    private var collectionEntriesRefreshTask: Task<Void, Never>?
    private var imageCacheObserversInstalled = false
    private var descriptionEditorSessions: [String: DescriptionEditorSession] = [:]
    private var networkPathMonitor: NWPathMonitor?
    /// Debounce path flap → reconnect so brief NWPathMonitor blips don't tear down a healthy socket.
    private var networkReconnectDebounceTask: Task<Void, Never>?
    private var wireSnapshotRefreshTasks: [String: Task<Void, Never>] = [:]
    private var documentLoadContinuations: [String: CheckedContinuation<Bool, Never>] = [:]
    private var documentLoadTasks: [String: Task<Bool, Never>] = [:]
    private var isNetworkReachable = true

    private var currentSocketSessionContext: SyncSocketSessionContext? {
        switch connectionStep {
        case .disconnected:
            return nil
        case .connecting(let context), .authenticating(let context), .authenticated(let context):
            return context
        }
    }

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
        guard let userId else {
            unsyncedRecipeIds = []
            return
        }
        unsyncedRecipeIds = (try? await store.loadUnsyncedRecipeIds(userId: userId)) ?? []
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
                try? await store.setRecipeUnsynced(
                    recipeId: recipeId,
                    userId: userId,
                    unsynced: true
                )
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
        guard let userId else { return }
        try? await store.setRecipeUnsynced(
            recipeId: recipeId,
            userId: userId,
            unsynced: true
        )
    }

    /// Clear the unsynced flag once the server acknowledges the recipe (`sync_confirmed`/delete).
    private func markRecipeSynced(_ recipeId: String) async {
        guard unsyncedRecipeIds.remove(recipeId) != nil else { return }
        guard let userId else { return }
        try? await store.setRecipeUnsynced(
            recipeId: recipeId,
            userId: userId,
            unsynced: false
        )
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

    /// Preview/test factory: builds a `YjsSyncService` with stand-alone
    /// dependencies wired explicitly through the designated initializer.
    /// Production code goes through `AppContainer`, which constructs the full
    /// dependency graph. Use this in `#Preview` and XCTest instead of reaching
    /// for service `.shared` singletons inside the initializer.
    static func makeForTesting(store: YDocStore) -> YjsSyncService {
        YjsSyncService(
            store: store,
            timerSync: TimerSyncService.shared,
            pushRegistration: PushRegistrationService.shared,
            recipeImage: RecipeImageService.shared,
            yjsMergeHelper: YjsMergeHelper.shared
        )
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
        guard let userId else { return }
        await flushPendingEdits(userId: userId)
    }

    private func flushPendingEdits(userId: String) async {
        guard self.userId == userId else { return }
        guard let recipeId = activeRecipeId else { return }
        // 1) WebView debounced Yjs → yrs (waits for apply chain)
        if let bridge = descriptionEditorSessions[recipeId]?.bridge {
            await bridge.flushEditorEdits()
        }
        guard self.userId == userId else { return }
        // 2) Local SQLite snapshot (description editor uses debounced persist)
        await documentManager.flushScheduledSnapshotPersist(
            docKey: docKeyFor(recipeId: recipeId, userId: userId)
        )
        guard self.userId == userId else { return }
        // 3) Drain debouncer (WebView flush posts yjs encodeStateAsUpdate via syncState)
        let recipeIds = pendingEditRecipeIds()
        for id in recipeIds {
            guard self.userId == userId else { return }
            await updateDebouncer.flushNow(userId: userId, recipeId: id)
        }
        for id in recipeIds {
            guard self.userId == userId else { return }
            await documentManager.persistSnapshot(docKey: docKeyFor(recipeId: id, userId: userId))
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

    private func flushPendingUpdates(for recipeIds: [String], userId: String) async {
        guard self.userId == userId else { return }
        for recipeId in recipeIds {
            guard self.userId == userId else { return }
            guard let batch = await updateDebouncer.drainPendingBatch(
                userId: userId,
                recipeId: recipeId
            ) else {
                continue
            }
            guard self.userId == batch.userId, self.userId == userId else { return }
            let payloads = batch.updates.filter { $0.count > 2 }
            guard !payloads.isEmpty else { continue }
            if payloads.count == 1 {
                await sendDebouncedUpdate(userId: userId, recipeId: recipeId, update: payloads[0])
            } else if let merged = try? await yjsMergeHelper.mergeUpdates(payloads) {
                guard self.userId == userId else { return }
                await sendDebouncedUpdate(userId: userId, recipeId: recipeId, update: merged)
            } else {
                for payload in payloads {
                    guard self.userId == userId else { return }
                    await sendDebouncedUpdate(userId: userId, recipeId: recipeId, update: payload)
                }
            }
        }
        for recipeId in recipeIds {
            guard self.userId == userId else { return }
            await documentManager.persistSnapshot(docKey: docKeyFor(recipeId: recipeId, userId: userId))
        }
    }

    private func canSendLiveSync() -> Bool {
        isNetworkReachable
            && connectionState.isConnected
            && socket?.status == .connected
            && isSocketAuthenticated
    }

    private func canSendCollectionSync() -> Bool {
        collectionHandshakeState == .ready
            && collectionHandshakeContext == currentSocketSessionContext
            && canSendLiveSync()
    }

    private func isCurrentSession(
        _ context: SyncSocketSessionContext,
        requireAuthenticated: Bool = true
    ) -> Bool {
        guard isCurrentSocketSession(context),
              userId == context.userId,
              let socket,
              ObjectIdentifier(socket) == context.clientIdentifier,
              socket.status == .connected else {
            return false
        }
        return !requireAuthenticated || isSocketAuthenticated
    }

    private func isCurrentSession(
        _ context: SyncSocketSessionContext,
        client: SocketIOClient,
        requireAuthenticated: Bool = true
    ) -> Bool {
        isCurrentSession(context, requireAuthenticated: requireAuthenticated)
            && ObjectIdentifier(client) == context.clientIdentifier
            && client.status == .connected
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
        queuedRecipeIds: Set<String>? = nil,
        userId: String? = nil
    ) async -> Bool {
        guard let accountId = userId ?? self.userId,
              self.userId == accountId else {
            return false
        }
        if unsyncedRecipeIds.contains(recipeId) { return true }
        switch writeSyncStates[recipeId] ?? .idle {
        case .queued, .syncing, .pendingLocal:
            return true
        case .idle, .synced, .error:
            break
        }
        if let queuedRecipeIds {
            if queuedRecipeIds.contains(recipeId) { return true }
        } else if let entries = try? await offlineQueue.fetch(forRecipeId: recipeId) {
            guard self.userId == accountId else { return false }
            let docKey = docKeyFor(recipeId: recipeId, userId: accountId)
            if entries.contains(where: { $0.docKey == docKey }) {
                return true
            }
        }
        let pendingObserver = await documentManager.pendingSyncByteCount(recipeId: recipeId)
        guard self.userId == accountId else { return false }
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
        guard let sessionContext = currentSocketSessionContext else { return }
        await syncPendingDocumentsAfterReconnect(
            recipeIds: recipeIds,
            sessionContext: sessionContext
        )
    }

    private func syncPendingDocumentsAfterReconnect(
        recipeIds: [String]?,
        sessionContext: SyncSocketSessionContext
    ) async {
        pendingReconnectSyncTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.isCurrentSession(sessionContext) else { return }
            await self.flushPendingEdits(userId: sessionContext.userId)
            guard !Task.isCancelled, self.isCurrentSession(sessionContext) else { return }
            await self.documentManager.applyOfflineQueueToLocalDocs(userId: sessionContext.userId)
            guard !Task.isCancelled, self.isCurrentSession(sessionContext) else { return }
            let candidates = recipeIds ?? self.collectionEntries.map(\.id)
            await self.fetchAndMergeServerDocuments(
                recipeIds: candidates,
                userId: sessionContext.userId,
                sessionContext: sessionContext
            )
            guard !Task.isCancelled, self.isCurrentSession(sessionContext) else { return }
            await self.refreshWireSnapshotsForRecipes(
                recipeIds: candidates,
                userId: sessionContext.userId,
                sessionContext: sessionContext
            )
            guard !Task.isCancelled, self.isCurrentSession(sessionContext) else { return }
            await self.drainWhenLiveSyncReady(
                recipeIds: candidates,
                sessionContext: sessionContext
            )
            guard !Task.isCancelled, self.isCurrentSession(sessionContext) else { return }
            await self.scheduleDescriptionWireExportIfNeeded(
                recipeIds: candidates,
                userId: sessionContext.userId,
                sessionContext: sessionContext
            )
            guard !Task.isCancelled, self.isCurrentSession(sessionContext) else { return }
            if let active = self.activeRecipeId {
                await self.refreshCurrentRecipeIfAllowed(recipeId: active)
            }
        }
        pendingReconnectSyncTask = task
        await task.value
    }

    private func drainWhenLiveSyncReady(
        recipeIds: [String],
        sessionContext: SyncSocketSessionContext
    ) async {
        let maxAttempts = 50
        for _ in 0..<maxAttempts {
            guard !Task.isCancelled, isCurrentSession(sessionContext) else { return }
            if canSendLiveSync() {
                await drainOfflineQueue(sessionContext: sessionContext)
                guard !Task.isCancelled, isCurrentSession(sessionContext) else { return }
                await pushUnsyncedWireSnapshots(
                    recipeIds: recipeIds,
                    sessionContext: sessionContext
                )
                return
            }
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                return
            }
        }
    }

    /// Web parity: pull server snapshot and CRDT-merge into local before pushing offline edits.
    private func fetchAndMergeServerDocuments(
        recipeIds: [String],
        userId: String? = nil,
        sessionContext: SyncSocketSessionContext? = nil
    ) async {
        let accountId = sessionContext?.userId ?? userId ?? self.userId
        guard let accountId, self.userId == accountId else { return }
        if let userId {
            guard self.userId == userId else { return }
        }
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        }
        guard canSendLiveSync() else { return }
        let queueEntries = (try? await offlineQueue.fetchAll()) ?? []
        guard self.userId == accountId else { return }
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        }
        let ownedPrefix = "\(accountId):"
        let queuedRecipeIds = Set(
            queueEntries
                .filter { $0.docKey.hasPrefix(ownedPrefix) }
                .map(\.recipeId)
        )
        for recipeId in recipeIds where isRecipeDocument(recipeId: recipeId) {
            if let sessionContext {
                guard isCurrentSession(sessionContext) else { return }
            }
            guard await hasUnsyncedLocalChanges(
                recipeId: recipeId,
                queuedRecipeIds: queuedRecipeIds,
                userId: accountId
            ) else { continue }
            _ = await fetchAndMergeServerDocument(
                recipeId: recipeId,
                sessionContext: sessionContext
            )
        }
    }

    private func fetchAndMergeServerDocument(
        recipeId: String,
        sessionContext: SyncSocketSessionContext? = nil
    ) async -> Bool {
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return false }
        }
        guard canSendLiveSync() else { return false }
        if let existingTask = documentLoadTasks[recipeId] {
            let result = await existingTask.value
            if let sessionContext {
                guard isCurrentSession(sessionContext) else { return false }
            }
            return result
        }
        let task = Task { @MainActor in
            if let sessionContext {
                guard self.isCurrentSession(sessionContext) else { return false }
            }
            let result = await withTaskGroup(of: Bool.self) { group in
                group.addTask { @MainActor in
                    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                        self.documentLoadContinuations[recipeId] = continuation
                        guard let userId = sessionContext?.userId ?? self.userId else {
                            continuation.resume(returning: false)
                            return
                        }
                        let docKey = self.docKeyFor(recipeId: recipeId, userId: userId)
                        self.emitSyncStep1(
                            recipeId: recipeId,
                            docKey: docKey,
                            documentKind: nil,
                            sessionContext: sessionContext
                        )
                        self.logger.info("Emitted sync_step1 for merge \(recipeId)")
                    }
                }
                group.addTask {
                    do {
                        try await Task.sleep(nanoseconds: 10_000_000_000)
                    } catch {
                        return false
                    }
                    return false
                }
                let res = await group.next() ?? false
                group.cancelAll()
                return res
            }
            if let sessionContext {
                guard self.isCurrentSession(sessionContext) else {
                    self.completePendingDocumentLoad(recipeId: recipeId, merged: false)
                    return false
                }
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

    private func scheduleDescriptionWireExportIfNeeded(
        recipeIds: [String],
        userId: String,
        sessionContext: SyncSocketSessionContext
    ) async {
        guard self.userId == userId, isCurrentSession(sessionContext) else { return }
        for recipeId in recipeIds where isRecipeDocument(recipeId: recipeId) {
            guard await hasUnsyncedLocalChanges(
                recipeId: recipeId,
                userId: userId
            ) else { continue }
            guard self.userId == userId, isCurrentSession(sessionContext) else { return }
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
        guard let userId else { return }
        let docKey = docKeyFor(recipeId: recipeId, userId: userId)
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
                        let disconnectedUserId = self.userId
                        if let disconnectedUserId {
                            Task { @MainActor [weak self] in
                                guard let self else { return }
                                await self.flushPendingUpdates(
                                    for: self.pendingEditRecipeIds(),
                                    userId: disconnectedUserId
                                )
                            }
                            Task { @MainActor [weak self] in
                                await self?.flushPendingEdits(userId: disconnectedUserId)
                            }
                        }
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

    /// Wait up to `timeoutSeconds` for the WebSocket to reach `.connected`.
    ///
    /// Returns `true` immediately if already connected, otherwise polls every 200ms
    /// until the deadline expires. Used by `NativeExportImportService.importFile` so
    /// that an incoming `.recipe` file opened right after app launch (when WS is
    /// still in `.reconnecting`) can still upload its photo instead of being
    /// skipped as offline. Never throws.
    func waitForConnection(timeoutSeconds: Double) async -> Bool {
        if connectionState == .connected { return true }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if connectionState == .connected { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return connectionState == .connected
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
        guard let userId else { return }
        await markRecipeUnsynced(recipeId)
        let docKey = docKeyFor(recipeId: recipeId, userId: userId)
        guard self.userId == userId else { return }
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
        guard self.userId == userId else { return }
        await persistYjsWireSnapshot(recipeId: recipeId, state: state)
        guard self.userId == userId else { return }
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
            _ = await emitSyncUpdate(
                recipeId: recipeId,
                update: state,
                docKey: docKey,
                sessionContext: currentSocketSessionContext
            )
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
            guard let userId, self.userId == userId else { return }
            await flushPendingUpdates(for: recipeIds, userId: userId)
            guard self.userId == userId else { return }
            let recipePending = await updateDebouncer.hasPending(userId: userId, recipeId: recipeId)
            let collectionPending = await updateDebouncer.hasPending(userId: userId, recipeId: "collection")
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

    /// DEBUG-only re-export of the screenshot-seed shopping list replace.
    /// See `DocumentManager.replaceShoppingItems` for the rationale.
    #if DEBUG
    func replaceShoppingItems(_ items: [ShoppingListItem]) async throws {
        try await documentManager.replaceShoppingItems(items)
        await refreshShoppingSnapshot()
    }
    #endif

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
        _ = try? await documentManager.getOrCreateDoc(
            key: docKeyFor(recipeId: recipeId, userId: userId)
        )
        guard self.userId == userId else { throw RecipeEditError.documentNotLoaded }
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
            teardownSocket()
            if let previousUserId = self.userId {
                await updateDebouncer.cancel(userId: previousUserId)
            }
            await documentManager.clearOfflineQueueForAccountSwitch()
            writeSyncStates = [:]
            unsyncedRecipeIds = []
        }
        let sessionUserId = userId
        self.userId = userId
        // Cold start: `self.userId` was nil so the switch clear above is skipped, but
        // SQLite may still hold another account's offline rows — purge them before drain.
        if let purged = try? await offlineQueue.clearNotOwnedBy(userId: userId), purged > 0 {
            AppLog.info(.sync, "offline_queue_purged_foreign", data: [
                "removed": "\(purged)",
            ])
            logger.info("Purged \(purged) offline queue row(s) not owned by current user")
        }
        await migratePlistSyncKeysIfNeeded(userId: userId)
        await loadUnsyncedRecipeIds()
        startNetworkMonitorIfNeeded()
        await documentManager.setUserId(sessionUserId)

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
        guard let userId else { return }
        activeRecipeId = recipeId
        await installChangeHandlersIfNeeded()

        let docKey = docKeyFor(recipeId: recipeId, userId: userId)
        _ = try? await documentManager.getOrCreateDoc(key: docKey)
        guard self.userId == userId else { return }
        await refreshCurrentRecipe(recipeId: recipeId)
        guard self.userId == userId else { return }


        guard socket?.status == .connected, isSocketAuthenticated else { return }

        // Offline-first (web parity): local snapshot is shown immediately above; only pull
        // server state when there is nothing waiting to be pushed outward.
        if await hasUnsyncedLocalChanges(recipeId: recipeId) {
            await syncPendingDocumentsAfterReconnect(recipeIds: [recipeId])
            if await hasUnsyncedLocalChanges(recipeId: recipeId) {
                logger.info("Skipping sync_step1 for \(recipeId) — unsynced local changes")
                return
            }
        }

        emitSyncStep1(
            recipeId: recipeId,
            docKey: docKey,
            documentKind: nil,
            sessionContext: currentSocketSessionContext
        )
        logger.info("Emitted sync_step1 for recipe \(recipeId)")
    }

    /// After `POST /api/v2/recipes/:id/copy`: pull server recipe + collection, ensure
    /// collection metadata has `imageUrl`, and warm on-disk preview cache for the new id.
    func integrateCopiedRecipe(recipeId: String, fallbackImageUrl: String?) async {
        guard userId != nil else { return }
        activeRecipeId = recipeId
        await installChangeHandlersIfNeeded()

        if canSendLiveSync() {
            _ = await fetchAndMergeServerDocument(
                recipeId: recipeId,
                sessionContext: currentSocketSessionContext
            )
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
        _ = try? await documentManager.getOrCreateDoc(
            key: docKeyFor(recipeId: recipeId, userId: userId)
        )
        guard self.userId == userId else { return nil }
        return try? await documentManager.readRecipeData(recipeId: recipeId, userId: userId)
    }

    /// Lightweight search projection without XmlFragment→HTML conversion.
    func peekSearchIndex(recipeId: String) async -> RecipeSearchIndex? {
        guard let userId else { return nil }
        _ = try? await documentManager.getOrCreateDoc(
            key: docKeyFor(recipeId: recipeId, userId: userId)
        )
        guard self.userId == userId else { return nil }
        return try? await documentManager.readSearchIndex(recipeId: recipeId, userId: userId)
    }

    /// The current user id, exposed read-only for indexing layers (Spotlight, etc.).
    var currentUserId: String? { userId }

    var currentDeviceId: String { deviceId }

    /// Stop synchronization and clean up.
    func stop() {
        logger.info("Stopping YjsSync")
        teardownSocket()
        Task { await updateDebouncer.cancelAll() }
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
        if let userId {
            Task { @MainActor [weak self] in
                await self?.flushPendingEdits(userId: userId)
            }
        }
        teardownSocket()
        setConnectionState(.disconnected, reason: "app_background")
    }

    /// App returned to foreground. Re-establish proactively instead of waiting for the slow,
    /// timeout-driven Socket.IO auto-reconnect (a fresh connect completes in ~0.5s).
    func handleEnteredForeground() {
        guard let userId else { return }
        reconnectIfNeeded(reason: "Entered foreground")
        delayedReconnectSyncTask?.cancel()
        delayedReconnectSyncTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  let currentContext = self.currentSocketSessionContext,
                  currentContext.userId == userId,
                  self.isCurrentSession(currentContext) else { return }
            await self.syncPendingDocumentsAfterReconnect(
                recipeIds: nil,
                sessionContext: currentContext
            )
        }
    }

    /// User-driven reconnect from sync status UI. Always tears down and reconnects,
    /// even when the socket appears live (half-dead recovery).
    func forceReconnect() {
        guard userId != nil else { return }
        AppLog.info(.sync, "force_reconnect", data: [
            "previousState": "\(connectionState)",
            "transport": connectionTransport.rawValue,
        ])
        connectionTransport = .pollingAndWebsocket
        teardownSocket()
        connectSocket()
    }

    // MARK: - Socket.IO Connection

    private func teardownSocket() {
        clearInFlightOfflineTracking()
        transition(to: .disconnected)
        authRetryTask?.cancel()
        authRetryTask = nil
        for task in syncEmitTasks.values {
            task.cancel()
        }
        syncEmitTasks.removeAll()
        syncEmitTail?.cancel()
        syncEmitTail = nil
        pendingReconnectSyncTask?.cancel()
        pendingReconnectSyncTask = nil
        delayedReconnectSyncTask?.cancel()
        delayedReconnectSyncTask = nil
        delayedSyncErrorTask?.cancel()
        delayedSyncErrorTask = nil
        recipeBatchLoadTask?.cancel()
        recipeBatchLoadTask = nil
        socket?.disconnect()
        socket = nil
        manager = nil
        isSocketAuthenticated = false
        didEmitAuthThisSession = false
        hasRequestedCollectionLoad = false
        hasRequestedShoppingLoad = false
        collectionHandshakeState = .idle
        collectionHandshakeContext = nil
        collectionHandshakeState = .idle
        collectionHandshakeContext = nil
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
        cancelAllSyncStep1Probes()
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
        cancelSyncStep1Probe(recipeId: recipeId)
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
        // Socket.IO-Client-Swift measures reconnectWait in *seconds* (defaults 10/30),
        // not milliseconds — the web contract's "1000ms" maps to `1` here.
        var socketConfig: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWait(1),
            .reconnectWaitMax(5),
        ]
        if connectionTransport == .websocketOnly {
            socketConfig.insert(.forceWebsockets(true))
        }
        manager = SocketManager(socketURL: serverURL, config: socketConfig)

        let client = manager!.defaultSocket
        self.socket = client
        let sessionContext = SyncSocketSessionContext(
            sessionId: sessionId,
            userId: userId,
            client: client
        )
        if let deviceToken, !deviceToken.isEmpty {
            client.connect(withPayload: ["token": deviceToken])
        } else {
            client.connect()
        }

        // Socket lifecycle handlers
        client.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionContext) else { return }
                self.logger.info("Socket.IO connected")
                self.setConnectionState(.connecting, reason: "socket.connect")
                self.isSocketAuthenticated = false
                self.transition(to: .authenticating(context: sessionContext))
                self.emitAuth()
            }
        }

        // Server auth ack after `auth` (payload includes `message`). Do not treat bare engine connect as auth.
        client.on("connected") { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionContext) else { return }
                guard let payload = data.first as? [String: Any], payload["message"] != nil else {
                    return
                }
                // Server may ack multiple times if it received multiple `auth`
                // emits (e.g. transport upgrade races). Only the first ack should
                // drive the state machine; subsequent ones are no-ops.
                guard !self.isSocketAuthenticated else { return }
                self.logger.info("Socket.IO authenticated (server ack)")
                self.markAuthenticatedAndLoadCollection(context: sessionContext)
            }
        }

        client.on("timer_event") { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionContext) else { return }
                guard let payload = data.first as? [String: Any] else { return }
                self.timerSync.handleWebSocketPayload(payload)
            }
        }

        client.on("auth_error") { [weak self] data, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionContext) else { return }
                let message = data.first as? [String: Any]
                let detail = message?["message"] as? String ?? "Authentication failed"
                // Log the raw server detail for diagnostics, but never route it to the UI —
                // a compromised server or MITM could otherwise inject arbitrary text into
                // the trusted sync banner (`ConnectionState.displayLabel`). MIK-163.
                self.logger.error("Socket.IO auth_error: \(detail)")

                // Spec 055 Phase R: server confirms post-commit account
                // deletion via `realtime.disconnectUser(user, "Account deleted")`.
                // Hand off to the runtime recovery flow (seed exchange +
                // wipe) instead of just surfacing a stuck error banner.
                if detail == AuthRevocationConstants.accountDeletedSocketMessage {
                    self.logger.notice("Socket.IO auth_error: account deleted signal — delegating to AuthService")
                    await self.authInvalidationHandler?(.socketSignal)
                    return
                }

                let userMessage = Bundle.currentLocalizedString("connection.state.auth-error")
                self.setConnectionState(.error(userMessage), reason: "auth_error")
            }
        }

        client.on(clientEvent: .disconnect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isCurrentSocketSession(sessionContext) else {
                    return
                }
                self.logger.info("Socket.IO disconnected")
                self.isSocketAuthenticated = false
                self.didEmitAuthThisSession = false
                self.hasRequestedCollectionLoad = false
                self.hasRequestedShoppingLoad = false
                self.collectionHandshakeState = .idle
                self.collectionHandshakeContext = nil
                self.transition(to: .disconnected)
                self.disconnectTimestamp = Date()
                self.recipeBatchLoadTask?.cancel()
                self.recipeBatchLoadTask = nil
                self.recipeBatchLoadInFlight = false
                self.recipeBatchLoadCompleted = 0
                self.recipeBatchLoadTotal = 0
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.flushPendingUpdates(
                        for: self.pendingEditRecipeIds(),
                        userId: sessionContext.userId
                    )
                }
                // Auto-reconnect is enabled — show reconnecting, not "Offline".
                self.setConnectionState(.reconnecting, reason: "socket.disconnect")
            }
        }

        client.on(clientEvent: .reconnectAttempt) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionContext) else { return }
                self.isSocketAuthenticated = false
                self.didEmitAuthThisSession = false
                self.hasRequestedCollectionLoad = false
                self.hasRequestedShoppingLoad = false
                self.collectionHandshakeState = .idle
                self.collectionHandshakeContext = nil
                self.setConnectionState(.reconnecting, reason: "reconnect_attempt")
            }
        }

        // Auth is emitted from `.connect` only — `reconnect` fires before the engine is ready.
        client.on(clientEvent: .reconnect) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isCurrentSocketSession(sessionContext) else { return }
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
                guard let self, self.isCurrentSocketSession(sessionContext) else { return }
                let msg = data.first.map { String(describing: $0) } ?? "unknown"
                self.logger.error("Socket.IO error: \(msg)")
                AppLog.info(.sync, "socket_error", data: [
                    "error": String(msg.prefix(200)),
                    "socketStatus": "\(self.socket?.status.rawValue ?? -1)",
                    "connectionState": "\(self.connectionState)",
                ])
                // Engine/transport errors are transient: Socket.IO auto-reconnects.
                // Demoting UI on every error (esp. polling long-poll timeouts) flaps
                // offline ↔ online. Only leave `.connected` when the engine is gone.
                guard self.socket?.status != .connected else { return }
                self.isSocketAuthenticated = false
                self.setConnectionState(.reconnecting, reason: "socket.error")
            }
        }

        // Register sync protocol event handlers with immutable session context.
        eventHandler.registerHandlers(on: client, context: sessionContext)
        setConnectionState(.connecting, reason: "connect_socket_called")
        transition(to: .connecting(context: sessionContext))
    }

    private func isCurrentSocketSession(_ context: SyncSocketSessionContext) -> Bool {
        switch connectionStep {
        case .disconnected:
            return false
        case .connecting(let current), .authenticating(let current), .authenticated(let current):
            return current == context
        }
    }

    private func transition(to step: ConnectionStep) {
        connectionStepTimer?.cancel()
        connectionStepTimer = nil

        connectionStep = step

        switch step {
        case .disconnected:
            break

        case .connecting(let context):
            connectionStepTimer = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 8_000_000_000)
                } catch {
                    return
                }
                await MainActor.run {
                    guard let self else { return }
                    guard !Task.isCancelled, self.isCurrentSocketSession(context) else { return }
                    self.handleStuckEngineConnect(context: context, trigger: "engine_connect_timeout")
                }
            }

        case .authenticating(let context):
            connectionStepTimer = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    return
                }
                await MainActor.run {
                    guard let self else { return }
                    guard !Task.isCancelled, self.isCurrentSocketSession(context) else { return }
                    if self.isSocketAuthenticated { return }
                    guard self.socket?.status == .connected else { return }
                    self.logger.warning("Socket auth ack timeout; loading collection after delay")
                    self.markAuthenticatedAndLoadCollection(context: context)
                }
            }

        case .authenticated:
            break
        }
    }

    private func setConnectionState(_ state: ConnectionState, reason: String) {
        if connectionState != state {
            AppLog.info(.sync, "connection_state", data: [
                "from": "\(connectionState)",
                "to": "\(state)",
                "reason": reason,
            ])
        }
        connectionState = state
        if !state.isConnected {
            reconcileStuckSyncingStates()
        }
    }

    private func emitAuth() {
        if let token = SharedAuthStore.token, !token.isEmpty {
            return
        }
        guard let userId, let sessionContext = currentSocketSessionContext else { return }

        if performAuthEmit(userId: userId) {
            return
        }

        // `.connect` can fire before `status == .connected` — retry briefly (was causing infinite "Connecting…").
        authRetryTask?.cancel()
        authRetryTask = Task { @MainActor [weak self] in
            for _ in 1...15 {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled, self.isCurrentSession(
                    sessionContext,
                    requireAuthenticated: false
                ) else { return }
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

    private func handleStuckEngineConnect(context: SyncSocketSessionContext, trigger: String) {
        guard isCurrentSocketSession(context) else { return }
        guard !isSocketAuthenticated else { return }
        guard socket?.status != .connected else {
            transition(to: .authenticating(context: context))
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

    private func markAuthenticatedAndLoadCollection(context: SyncSocketSessionContext) {
        guard isCurrentSocketSession(context) else { return }
        transition(to: .authenticated(context: context))
        isSocketAuthenticated = true
        setConnectionState(.connected, reason: "authenticated")
        if disconnectTimestamp != nil {
            delayedReconnectSyncTask?.cancel()
            delayedReconnectSyncTask = Task { @MainActor [weak self] in
                // Let load/auth polling POSTs flush before large binary sync_updates.
                do {
                    try await Task.sleep(nanoseconds: 600_000_000)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled, self.isCurrentSession(context) else { return }
                await self.syncPendingDocumentsAfterReconnect(
                    recipeIds: nil,
                    sessionContext: context
                )
                guard !Task.isCancelled, self.isCurrentSession(context) else { return }
                self.reloadStaleDocumentsAfterReconnect()
            }
        } else {
            loadCollectionDocument()
            delayedReconnectSyncTask?.cancel()
            delayedReconnectSyncTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 600_000_000)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled, self.isCurrentSession(context) else { return }
                await self.syncPendingDocumentsAfterReconnect(
                    recipeIds: nil,
                    sessionContext: context
                )
            }
        }
        timerSync.initializeAfterAuth()
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentSession(context) else { return }
            await self.pushRegistration.registerIfNeeded()
        }
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
        guard let sessionContext = currentSocketSessionContext,
              isCurrentSession(sessionContext) else {
            logger.warning("Skipping sync_step1 (collection) — socket not connected")
            return
        }
        guard !hasRequestedCollectionLoad else { return }
        hasRequestedCollectionLoad = true
        collectionHandshakeState = .handshaking
        collectionHandshakeContext = sessionContext
        emitSyncStep1(
            recipeId: "collection",
            docKey: docKeyFor(recipeId: "collection", userId: sessionContext.userId),
            documentKind: nil,
            sessionContext: sessionContext
        )
        loadShoppingDocument()
    }

    private func loadShoppingDocument() {
        guard let sessionContext = currentSocketSessionContext,
              isCurrentSession(sessionContext) else { return }
        guard !hasRequestedShoppingLoad else { return }
        hasRequestedShoppingLoad = true
        let shoppingDocKey = Self.shoppingDocKey(userId: sessionContext.userId)
        emitSyncStep1(
            recipeId: ShoppingListConstants.offlineRecipeId,
            docKey: shoppingDocKey,
            documentKind: ShoppingListConstants.documentKind,
            sessionContext: sessionContext
        )
    }

    /// New primary load path (web parity). Sends the in-memory state vector;
    /// the server replies with `sync_step2` containing only the missing ops.
    /// `lastSyncedAt` is intentionally omitted — the new protocol does not
    /// use it (web `yjs-client.ts` sync_step1 path does the same).
    ///
    /// - Parameter forceEmptyStateVector: when true, send an empty SV so the
    ///   server returns the full canonical state (used by truncated-collection
    ///   recovery — mirrors web `recoverCollectionFromServer`).
    private func emitSyncStep1(
        recipeId: String,
        docKey: String,
        documentKind: String?,
        forceEmptyStateVector: Bool = false,
        sessionContext: SyncSocketSessionContext? = nil
    ) {
        guard let sessionContext = sessionContext ?? currentSocketSessionContext else { return }
        guard docKey == docKeyFor(recipeId: recipeId, userId: sessionContext.userId) else {
            logger.error("Skipping sync_step1 with mismatched doc key for \(recipeId)")
            return
        }
        Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.isCurrentSession(sessionContext) else { return }
            let sv: Data
            if forceEmptyStateVector || docKey.isEmpty {
                sv = Data()
            } else {
                sv = await self.documentManager.stateVectorForSync(key: docKey)
            }
            guard !Task.isCancelled, self.isCurrentSession(sessionContext) else { return }
            var payload: [String: Any] = ["stateVector": sv]
            if recipeId != "collection" {
                payload["recipeId"] = recipeId
            }
            if let documentKind {
                payload["documentKind"] = documentKind
            }
            guard let client = self.socket,
                  isCurrentSession(sessionContext, client: client) else {
                return
            }
            client.emit("sync_step1", payload)
            self.logger.info("Emitted sync_step1 for \(recipeId) (\(sv.count) bytes sv)")
            self.scheduleSyncStep1Probe(
                recipeId: recipeId,
                documentKind: documentKind,
                sessionContext: sessionContext
            )
        }
    }

    private func syncStep1ProbeKey(recipeId: String, documentKind: String?) -> String {
        if documentKind == ShoppingListConstants.documentKind {
            return ShoppingListConstants.offlineRecipeId
        }
        return recipeId
    }

    /// Web-parity safety: if `sync_step2` never arrives (pre-protocol server or
    /// dropped reply), fall back once to legacy `load_document`. Does **not**
    /// pin the client to legacy permanently — subsequent loads still try
    /// `sync_step1` first.
    private func scheduleSyncStep1Probe(
        recipeId: String,
        documentKind: String?,
        sessionContext: SyncSocketSessionContext
    ) {
        let key = syncStep1ProbeKey(recipeId: recipeId, documentKind: documentKind)
        pendingSyncStep1Probes[key]?.task.cancel()
        let task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.syncStep1ProbeWindowNs)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.isCurrentSession(sessionContext) else { return }
            guard self.pendingSyncStep1Probes[key]?.context == sessionContext else { return }
            self.pendingSyncStep1Probes.removeValue(forKey: key)
            self.emitLegacyLoadDocument(
                recipeId: recipeId,
                documentKind: documentKind,
                sessionContext: sessionContext
            )
        }
        pendingSyncStep1Probes[key] = (context: sessionContext, task: task)
    }

    private func cancelSyncStep1Probe(recipeId: String, documentKind: String? = nil) {
        let key = syncStep1ProbeKey(recipeId: recipeId, documentKind: documentKind)
        pendingSyncStep1Probes.removeValue(forKey: key)?.task.cancel()
    }

    private func cancelAllSyncStep1Probes() {
        for (_, entry) in pendingSyncStep1Probes {
            entry.task.cancel()
        }
        pendingSyncStep1Probes.removeAll()
    }

    private func emitLegacyLoadDocument(
        recipeId: String,
        documentKind: String?,
        sessionContext: SyncSocketSessionContext
    ) {
        guard isCurrentSession(sessionContext) else { return }
        guard let client = socket,
              isCurrentSession(sessionContext, client: client) else {
            return
        }
        if documentKind == ShoppingListConstants.documentKind {
            client.emit("load_document", ["documentKind": ShoppingListConstants.documentKind])
        } else if recipeId == "collection" {
            client.emit("load_document", [:] as [String: Any])
        } else {
            client.emit("load_document", ["recipeId": recipeId])
        }
        logger.warning(
            "sync_step1 probe timed out — falling back to load_document for \(recipeId)"
        )
    }

    /// Spec 054 / web parity: hard-deletes + saturated SV poison the local
    /// collection. Drop in-memory doc, SQLite snapshot, and queued collection
    /// pushes, then `sync_step1` with an empty state vector so the server
    /// sends the canonical collection. Recovery is always bound to the
    /// originating socket session; callers must pass the context they used to
    /// validate the session immediately before invoking this.
    private func recoverCollectionFromServer(context: SyncSocketSessionContext) async {
        guard isCurrentSession(context) else { return }
        collectionHandshakeState = .recovering
        collectionHandshakeContext = context
        let docKey = docKeyFor(recipeId: "collection", userId: context.userId)
        logger.warning(
            "Recovering truncated collection — drop local state and empty-SV sync_step1"
        )

        clearInFlightOfflineTracking(forDocKey: docKey)
        _ = await updateDebouncer.drainPendingBatch(
            userId: context.userId,
            recipeId: "collection"
        )
        guard isCurrentSession(context) else { return }
        try? await store.deleteOfflineQueue(forDocKey: docKey)
        try? await store.deleteSnapshot(docKey: docKey)
        guard isCurrentSession(context) else { return }
        await documentManager.evictDoc(key: docKey)

        cancelSyncStep1Probe(recipeId: "collection")
        hasRequestedCollectionLoad = false
        guard isCurrentSession(context) else { return }
        hasRequestedCollectionLoad = true
        emitSyncStep1(
            recipeId: "collection",
            docKey: docKey,
            documentKind: nil,
            forceEmptyStateVector: true,
            sessionContext: context
        )
    }

    // MARK: - Event Handler Wiring

    private func wireEventHandler() {
        eventHandler.onDocumentLoaded = { [weak self] context, recipeId, stateData, lastSyncedAt in
            Task { @MainActor in
                await self?.handleDocumentLoaded(
                    context: context,
                    recipeId: recipeId,
                    stateData: stateData,
                    lastSyncedAt: lastSyncedAt
                )
            }
        }

        eventHandler.onDocumentsLoaded = { [weak self] context, documents in
            Task { @MainActor in
                await self?.handleDocumentsLoaded(context: context, documents: documents)
            }
        }

        eventHandler.onSyncStep2WithContext = { [weak self] context, recipeId, missingUpdate, lastSyncedAt, collectionSummary in
            Task { @MainActor in
                await self?.handleSyncStep2(
                    context: context,
                    recipeId: recipeId,
                    missingUpdate: missingUpdate,
                    lastSyncedAt: lastSyncedAt,
                    collectionSummary: collectionSummary
                )
            }
        }

        eventHandler.onRecipeUpdated = { [weak self] context, recipeId, updateData in
            Task { @MainActor in
                await self?.handleRecipeUpdated(context: context, recipeId: recipeId, updateData: updateData)
            }
        }

        eventHandler.onCollectionUpdated = { [weak self] context, updateData in
            Task { @MainActor in
                await self?.handleCollectionUpdated(context: context, updateData: updateData)
            }
        }

        eventHandler.onShoppingListUpdated = { [weak self] context, updateData in
            Task { @MainActor in
                await self?.handleShoppingListUpdated(context: context, updateData: updateData)
            }
        }

        eventHandler.onSyncError = { [weak self] context, code, message, recipeId in
            Task { @MainActor in
                await self?.handleSyncError(
                    context: context,
                    code: code,
                    message: message,
                    recipeId: recipeId
                )
            }
        }

        eventHandler.onSyncConfirmed = { [weak self] context, recipeId, lastSyncedAt in
            Task { @MainActor in
                await self?.handleSyncConfirmed(
                    context: context,
                    recipeId: recipeId,
                    lastSyncedAt: lastSyncedAt
                )
            }
        }
    }

    private func handleLocalRecipeUpdate(recipeId: String, update: Data) async {
        guard let userId else { return }
        await markRecipeUnsynced(recipeId)
        writeSyncStates[recipeId] = .pendingLocal
        await updateDebouncer.schedule(userId: userId, recipeId: recipeId, update: update)
    }

    private func handleDescriptionYjsUpdate(recipeId: String, update: Data) async {
        guard !update.isEmpty, update.count > 2 else { return }
        guard let userId else { return }
        await markRecipeUnsynced(recipeId)
        writeSyncStates[recipeId] = .pendingLocal
        let docKey = docKeyFor(recipeId: recipeId, userId: userId)
        guard self.userId == userId else { return }
        if !canSendLiveSync() {
            writeSyncStates[recipeId] = .queued
            try? await offlineQueue.enqueue(docKey: docKey, recipeId: recipeId, yjsUpdate: update)
            guard self.userId == userId else { return }
            await documentManager.persistSnapshot(docKey: docKey)
            guard self.userId == userId else { return }
            scheduleWireSnapshotRefresh(recipeId: recipeId, userId: userId)
            logger.info("Eager offline enqueue for description \(recipeId) (\(update.count) bytes)")
            return
        }
        await updateDebouncer.schedule(userId: userId, recipeId: recipeId, update: update)
    }

    private func scheduleWireSnapshotRefresh(recipeId: String, userId: String? = nil) {
        let capturedUserId = userId ?? self.userId
        wireSnapshotRefreshTasks[recipeId]?.cancel()
        let capturedContext = currentSocketSessionContext
        wireSnapshotRefreshTasks[recipeId] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            if let capturedUserId {
                guard self.userId == capturedUserId else { return }
                if let capturedContext {
                    guard self.isCurrentSession(capturedContext) else { return }
                }
                await self.refreshWireSnapshotForRecipe(
                    recipeId: recipeId,
                    userId: capturedUserId
                )
            } else {
                return
            }
            self.wireSnapshotRefreshTasks.removeValue(forKey: recipeId)
        }
    }

    private func refreshWireSnapshotsForRecipes(
        recipeIds: [String],
        userId: String? = nil,
        sessionContext: SyncSocketSessionContext? = nil
    ) async {
        guard let userId = userId ?? self.userId, self.userId == userId else { return }
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        }
        let candidates = recipeIds.filter { isRecipeDocument(recipeId: $0) }
        guard !candidates.isEmpty else { return }
        let allQueue = (try? await offlineQueue.fetchAll()) ?? []
        let ownedPrefix = "\(userId):"
        let queuedRecipeIds = Set(
            allQueue
                .filter { $0.docKey.hasPrefix(ownedPrefix) }
                .map(\.recipeId)
        )
        guard self.userId == userId else { return }
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        }
        let docKeys = candidates.map { docKeyFor(recipeId: $0, userId: userId) }
        let wireSnapshots = (try? await store.loadYjsWireSnapshots(docKeys: docKeys)) ?? [:]
        let snapshots = (try? await store.loadSnapshots(docKeys: docKeys)) ?? [:]
        guard self.userId == userId else { return }
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        }
        var queueByRecipeId: [String: [OfflineSyncEntry]] = [:]
        for entry in allQueue {
            guard entry.docKey.hasPrefix(ownedPrefix) else { continue }
            queueByRecipeId[entry.recipeId, default: []].append(entry)
        }
        for recipeId in candidates {
            if let sessionContext {
                guard isCurrentSession(sessionContext) else { return }
            }
            guard await hasUnsyncedLocalChanges(
                recipeId: recipeId,
                queuedRecipeIds: queuedRecipeIds,
                userId: userId
            ) else { continue }
            let docKey = docKeyFor(recipeId: recipeId, userId: userId)
            await refreshWireSnapshotForRecipe(
                recipeId: recipeId,
                userId: userId,
                wireSnapshot: wireSnapshots[docKey],
                snapshot: snapshots[docKey],
                queueEntries: queueByRecipeId[recipeId] ?? []
            )
        }
    }

    /// Rebuild durable yjs wire bytes from wire/yrs bootstrap + queued incrementals (never stale wire alone).
    private func refreshWireSnapshotForRecipe(
        recipeId: String,
        userId: String? = nil,
        wireSnapshot: YjsWireSnapshot? = nil,
        snapshot: YDocSnapshot? = nil,
        queueEntries: [OfflineSyncEntry]? = nil
    ) async {
        guard let userId = userId ?? self.userId, self.userId == userId else { return }
        let docKey = docKeyFor(recipeId: recipeId, userId: userId)
        let resolvedQueueEntries: [OfflineSyncEntry]
        if let queueEntries {
            resolvedQueueEntries = queueEntries
        } else {
            // Debounced single-recipe path: SQL filter, not full-queue scan (MIK-173).
            resolvedQueueEntries = ((try? await offlineQueue.fetch(forRecipeId: recipeId)) ?? [])
                .filter { $0.docKey == docKey }
        }
        guard self.userId == userId else { return }
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
        guard self.userId == userId else { return }
        try? await store.saveYjsWireSnapshot(docKey: docKey, state: full)
    }

    private func sendDebouncedUpdate(userId: String, recipeId: String, update: Data) async {
        guard self.userId == userId else { return }
        let docKey = docKeyFor(recipeId: recipeId, userId: userId)
        let sessionContext = currentSocketSessionContext

        if recipeId == "collection", !canSendCollectionSync() {
            writeSyncStates[recipeId] = .queued
            try? await offlineQueue.enqueue(docKey: docKey, recipeId: recipeId, yjsUpdate: update)
            guard self.userId == userId else { return }
            await documentManager.persistSnapshot(docKey: docKey)
            return
        }

        if canSendLiveSync() {
            writeSyncStates[recipeId] = .syncing
            let emitted = await emitSyncUpdate(
                recipeId: recipeId,
                update: update,
                docKey: docKey,
                sessionContext: sessionContext
            )
            guard self.userId == userId else { return }
            if !emitted {
                writeSyncStates[recipeId] = .queued
                try? await offlineQueue.enqueue(
                    docKey: docKey,
                    recipeId: recipeId,
                    yjsUpdate: update
                )
            }
            // Web parity: persist local state on every outbound attempt, not only on sync_confirmed.
            guard self.userId == userId else { return }
            await documentManager.persistSnapshot(docKey: docKey)
        } else {
            writeSyncStates[recipeId] = .queued
            try? await offlineQueue.enqueue(docKey: docKey, recipeId: recipeId, yjsUpdate: update)
            guard self.userId == userId else { return }
            await documentManager.persistSnapshot(docKey: docKey)
            logger.info("Queued offline update for \(recipeId) (\(update.count) bytes)")
        }
    }

    private func handleLocalShoppingUpdate(update: Data) async {
        guard let userId else { return }
        let sessionContext = currentSocketSessionContext
        let docKey = Self.shoppingDocKey(userId: userId)
        if let sessionContext, isCurrentSession(sessionContext) {
            let emitted = await emitSyncUpdate(
                recipeId: ShoppingListConstants.offlineRecipeId,
                update: update,
                docKey: docKey,
                documentKind: ShoppingListConstants.documentKind,
                sessionContext: sessionContext
            )
            guard self.userId == userId else { return }
            if emitted { return }
        }
        if self.userId == userId {
            try? await offlineQueue.enqueue(
                docKey: docKey,
                recipeId: ShoppingListConstants.offlineRecipeId,
                yjsUpdate: update
            )
            logger.info("Queued offline shopping update (\(update.count) bytes)")
        } else {
            return
        }
    }

    @discardableResult
    private func emitSyncUpdate(
        recipeId: String,
        update: Data,
        docKey: String,
        documentKind: String? = nil,
        sessionContext: SyncSocketSessionContext? = nil
    ) async -> Bool {
        guard let sessionContext = sessionContext ?? currentSocketSessionContext,
              let client = socket,
              isCurrentSession(sessionContext, client: client) else {
            return false
        }
        guard docKey == docKeyFor(recipeId: recipeId, userId: sessionContext.userId) else {
            return false
        }
        // New primary protocol: `sync_update` (web parity). The server applies
        // the update immediately and persists; `lastSyncedAt` is intentionally
        // omitted (legacy `sync_request` server path still accepts it for old
        // web/PWA, but the new event does not need it).
        //
        // Send raw `Data` so Socket.IO attaches it as a binary frame (web parity:
        // `Uint8Array`). A JSON `[UInt8]` array inflates ~3–4× and trips Engine.IO
        // `maxPayload` (1 MB default) — the POST fails, the socket dies, UI flaps
        // offline/reconnecting. Server accepts Uint8Array | number[].
        var payload: [String: Any] = [
            "yjsUpdate": update,
        ]
        // Collection and shopping list sync match web: omit `recipeId` (server rejects it for shopping).
        let isShoppingList = documentKind == ShoppingListConstants.documentKind
        if recipeId != "collection", !isShoppingList {
            payload["recipeId"] = recipeId
        }
        if let documentKind {
            payload["documentKind"] = documentKind
        }
        let target: String
        if documentKind == ShoppingListConstants.documentKind {
            target = "shoppingList"
        } else {
            target = recipeId == "collection" ? "collection" : recipeId
        }
        let isBinary = payload["yjsUpdate"] is Data
        let large = update.count > 32_768

        // Serialize emits: polling batches waiting posts into one HTTP body. Two
        // ~400KB binary sync_updates + sync_step1 became a ~1.1MB POST that
        // failed with `Error flushing waiting posts` and restarted the socket.
        let previous = syncEmitTail
        let taskId = UUID()
        let task = Task<Bool, Never> { @MainActor in
            if let previous {
                _ = await previous.value
            }
            guard !Task.isCancelled,
                  self.isCurrentSession(sessionContext, client: client) else {
                return false
            }
            if large {
                do {
                    try await Task.sleep(nanoseconds: 400_000_000)
                } catch {
                    return false
                }
                guard !Task.isCancelled,
                      self.isCurrentSession(sessionContext, client: client) else {
                    return false
                }
            }
            guard !Task.isCancelled,
                  self.isCurrentSession(sessionContext, client: client) else {
                return false
            }
            client.emit("sync_update", payload)
            self.logger.info("Emitted sync_update for \(target) (\(update.count) bytes, binary=\(isBinary))")
            AppLog.info(.sync, "sync_update_emitted", data: [
                "target": target,
                "bytes": "\(update.count)",
                "binary": isBinary ? "1" : "0",
            ])
            if large {
                // Allow the polling POST (base64 binary) to finish before the next large emit.
                do {
                    try await Task.sleep(nanoseconds: 900_000_000)
                } catch {
                    return false
                }
            }
            return !Task.isCancelled && self.isCurrentSession(sessionContext, client: client)
        }
        syncEmitTasks[taskId] = task
        syncEmitTail = task
        let result = await task.value
        syncEmitTasks.removeValue(forKey: taskId)
        return result
    }

    private func handleSyncConfirmed(
        context: SyncSocketSessionContext,
        recipeId: String,
        lastSyncedAt: String?
    ) async {
        let accountId = context.userId
        await handleSyncConfirmed(
            accountId: accountId,
            recipeId: recipeId,
            lastSyncedAt: lastSyncedAt,
            isSessionValid: { self.isCurrentSession(context) }
        )
    }

    private func handleSyncConfirmed(
        accountId: String,
        recipeId: String,
        lastSyncedAt: String?,
        isSessionValid: () -> Bool
    ) async {
        func sessionIsValid() -> Bool {
            isSessionValid()
        }
        guard sessionIsValid() else { return }
        guard recipeId != "unknown" else { return }
        let docKey = docKeyFor(recipeId: recipeId, userId: accountId)
        await acknowledgeOfflineBatch(docKey: docKey)
        guard sessionIsValid() else { return }
        lastSuccessfulSyncAt = Date()

        if let doc = await documentManager.getDoc(key: docKey),
           let state = await doc.encodeStateAsUpdate() {
            guard sessionIsValid() else { return }
            try? await store.saveSnapshot(docKey: docKey, state: state, lastSyncedAt: lastSyncedAt)
            guard sessionIsValid() else { return }
        }

        if isRecipeDocument(recipeId: recipeId) {
            try? await store.deleteYjsWireSnapshot(docKey: docKey)
            guard sessionIsValid() else { return }
        }

        if isRecipeDocument(recipeId: recipeId) {
            let stillQueued = ((try? await offlineQueue.fetch(forRecipeId: recipeId)) ?? [])
                .contains { $0.docKey == docKey }
            guard sessionIsValid() else { return }
            if stillQueued {
                await markRecipeUnsynced(recipeId)
                guard sessionIsValid() else { return }
                writeSyncStates[recipeId] = .queued
            } else {
                await markRecipeSynced(recipeId)
                guard sessionIsValid() else { return }
                writeSyncStates[recipeId] = .synced
            }
        }
    }

    private func drainOfflineQueue(
        sessionContext: SyncSocketSessionContext? = nil
    ) async {
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        }
        guard canSendLiveSync() else { return }
        guard let userId else { return }
        if let sessionContext {
            guard sessionContext.userId == userId else { return }
        }
        guard let entries = try? await offlineQueue.fetchAll(), !entries.isEmpty else { return }
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        }

        expireInFlightOfflineBatchesIfNeeded()

        let ownedPrefix = "\(userId):"
        var byDocKey: [String: [OfflineSyncEntry]] = [:]
        var foreignIds: [Int64] = []
        for entry in entries {
            if entry.docKey.hasPrefix(ownedPrefix) {
                byDocKey[entry.docKey, default: []].append(entry)
            } else if let id = entry.id {
                foreignIds.append(id)
            }
        }
        if !foreignIds.isEmpty {
            try? await offlineQueue.deleteEntries(ids: foreignIds)
            AppLog.info(.sync, "offline_drain_dropped_foreign", data: [
                "removed": "\(foreignIds.count)",
            ])
        }
        guard !byDocKey.isEmpty else { return }
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        }

        for (docKey, docEntries) in byDocKey {
            let firstRecipeId = docEntries.first?.recipeId
            if firstRecipeId == "collection", !canSendCollectionSync() {
                continue
            }
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
            if let sessionContext {
                guard isCurrentSession(sessionContext) else { return }
            }
            guard let pushData, pushData.count > 2 else { continue }
            let documentKind = recipeId == ShoppingListConstants.offlineRecipeId
                ? ShoppingListConstants.documentKind
                : nil
            if recipeId != ShoppingListConstants.offlineRecipeId {
                writeSyncStates[recipeId] = .syncing
            }
            let emitted = await emitSyncUpdate(
                recipeId: recipeId,
                update: pushData,
                docKey: docKey,
                documentKind: documentKind,
                sessionContext: sessionContext
            )
            if let sessionContext {
                guard isCurrentSession(sessionContext) else { return }
            }
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

    private func pushUnsyncedWireSnapshots(
        recipeIds: [String],
        userId: String? = nil,
        sessionContext: SyncSocketSessionContext? = nil
    ) async {
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        }
        if let userId {
            guard self.userId == userId else { return }
        }
        guard canSendLiveSync() else { return }
        let queued = (try? await offlineQueue.fetchAll()) ?? []
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        }
        if let userId {
            guard self.userId == userId else { return }
        }
        let resolvedUserId = userId ?? sessionContext?.userId ?? self.userId
        guard let resolvedUserId, self.userId == resolvedUserId else { return }
        let ownedPrefix = "\(resolvedUserId):"
        for recipeId in recipeIds {
            if let userId {
                guard self.userId == userId else { return }
            }
            guard isRecipeDocument(recipeId: recipeId) else { continue }
            guard await hasUnsyncedLocalChanges(
                recipeId: recipeId,
                queuedRecipeIds: Set(
                    queued
                        .filter { $0.docKey.hasPrefix(ownedPrefix) }
                        .map(\.recipeId)
                ),
                userId: resolvedUserId
            ) else { continue }
            let docKey = docKeyFor(recipeId: recipeId, userId: resolvedUserId)
            let queueEntries = queued.filter {
                $0.recipeId == recipeId && $0.docKey == docKey
            }
            if !queueEntries.isEmpty { continue }
            guard let pushData = await resolveYjsPushPayload(
                recipeId: recipeId,
                docKey: docKey,
                queueEntries: []
            ), pushData.count > 2 else { continue }
            if let sessionContext {
                guard isCurrentSession(sessionContext) else { return }
            }
            writeSyncStates[recipeId] = .syncing
            _ = await emitSyncUpdate(
                recipeId: recipeId,
                update: pushData,
                docKey: docKey,
                sessionContext: sessionContext
            )
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
        context: SyncSocketSessionContext? = nil,
        recipeId: String,
        docKey: String,
        stateData: Data,
        lastSyncedAt: String?
    ) async throws {
        if let context {
            guard isCurrentSession(context) else { throw SyncSessionError.stale }
        }
        // Web parity: CRDT-merge server state into local even when outbound queue is non-empty.
        let serverLooksEmpty = stateData.count <= 2
        var localState: Data?
        if let doc = await documentManager.getDoc(key: docKey) {
            localState = await doc.encodeStateAsUpdate()
        } else if let snapshot = try? await store.loadSnapshot(docKey: docKey) {
            localState = snapshot.state
        }
        if let context {
            guard isCurrentSession(context) else { throw SyncSessionError.stale }
        }
        let localBytes = localState?.count ?? 0
        let localLooksNonEmpty = localBytes > 2

        if serverLooksEmpty && localLooksNonEmpty, let localState {
            let documentKind = recipeId == ShoppingListConstants.offlineRecipeId
                ? ShoppingListConstants.documentKind
                : nil
            let emitted = await emitSyncUpdate(
                recipeId: recipeId,
                update: localState,
                docKey: docKey,
                documentKind: documentKind,
                sessionContext: context
            )
            guard emitted else {
                if context != nil { throw SyncSessionError.stale }
                return
            }
            return
        }

        if localLooksNonEmpty {
            try await documentManager.applyUpdate(
                key: docKey,
                data: stateData,
                lastSyncedAt: lastSyncedAt
            )
            if let context {
                guard isCurrentSession(context) else { throw SyncSessionError.stale }
            }
            logger.info("Merged server document into \(UserIdFormatter.redactDocKey(docKey)) (\(stateData.count) bytes)")
        } else {
            try await documentManager.replaceDocument(
                key: docKey,
                state: stateData,
                lastSyncedAt: lastSyncedAt
            )
            if let context {
                guard isCurrentSession(context) else { throw SyncSessionError.stale }
            }
        }
    }

    private func handleDocumentLoaded(
        context: SyncSocketSessionContext,
        recipeId: String,
        stateData: Data,
        lastSyncedAt: String?
    ) async {
        guard isCurrentSession(context) else { return }
        let docKey = docKeyFor(recipeId: recipeId, userId: context.userId)
        logger.info("document_loaded: \(UserIdFormatter.redactDocKey(docKey)), \(stateData.count) bytes")
        lastSuccessfulSyncAt = Date()
        cancelSyncStep1Probe(
            recipeId: recipeId,
            documentKind: recipeId == ShoppingListConstants.offlineRecipeId
                ? ShoppingListConstants.documentKind
                : nil
        )

        var mergeSucceeded = false
        do {
            try await applyServerDocumentState(
                context: context,
                recipeId: recipeId,
                docKey: docKey,
                stateData: stateData,
                lastSyncedAt: lastSyncedAt
            )
            mergeSucceeded = true
        } catch {
            logger.error("Failed to apply document state for \(UserIdFormatter.redactDocKey(docKey)): \(error)")
        }
        guard isCurrentSession(context) else { return }

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
        guard isCurrentSession(context) else { return }
    }

    /// `sync_step2` reply to our `sync_step1`. Contains only the ops the
    /// client is missing relative to the state vector it sent — primary
    /// load path going forward (web parity). When `missingUpdate` is empty
    /// (`count <= 2`) and the local doc is already non-empty, the client is
    /// already up to date and we no-op, just like web does.
    private func handleSyncStep2(
        context: SyncSocketSessionContext,
        recipeId: String,
        missingUpdate: Data,
        lastSyncedAt: String?,
        collectionSummary: CollectionSyncSummary? = nil
    ) async {
        guard isCurrentSession(context) else { return }
        let docKey = docKeyFor(recipeId: recipeId, userId: context.userId)
        logger.info("sync_step2: \(UserIdFormatter.redactDocKey(docKey)), \(missingUpdate.count) bytes")
        lastSuccessfulSyncAt = Date()
        cancelSyncStep1Probe(
            recipeId: recipeId,
            documentKind: recipeId == ShoppingListConstants.offlineRecipeId
                ? ShoppingListConstants.documentKind
                : nil
        )

        let serverSaysNothingNew = missingUpdate.count <= 2
        let existingSnapshot = try? await store.loadSnapshot(docKey: docKey)
        guard isCurrentSession(context) else { return }
        let localEmpty = existingSnapshot?.state.isEmpty ?? true

        if recipeId == "collection", serverSaysNothingNew, let collectionSummary {
            if await collectionIsTruncated(
                serverSummary: collectionSummary,
                docKey: docKey
            ) {
                await recoverCollectionFromServer(context: context)
                return
            }
        }

        if serverSaysNothingNew && !localEmpty {
            // Already in sync — no remote update to apply. Prefer in-memory
            // encodeStateAsUpdate (includes unsynced local edits). Never rewrite
            // with empty Data() from a second loadSnapshot that can race to nil.
            if let lastSyncedAt {
                if let doc = await documentManager.getDoc(key: docKey),
                   let state = await doc.encodeStateAsUpdate(),
                   !state.isEmpty {
                    guard isCurrentSession(context) else { return }
                    try? await store.saveSnapshot(docKey: docKey, state: state, lastSyncedAt: lastSyncedAt)
                } else if let existing = existingSnapshot, !existing.state.isEmpty {
                    guard isCurrentSession(context) else { return }
                    try? await store.saveSnapshot(docKey: docKey, state: existing.state, lastSyncedAt: lastSyncedAt)
                }
            }
            guard isCurrentSession(context) else { return }
            if isRecipeDocument(recipeId: recipeId) {
                completePendingDocumentLoad(recipeId: recipeId, merged: true)
            }
            if recipeId == ShoppingListConstants.offlineRecipeId {
                await refreshShoppingSnapshot()
            } else if recipeId == "collection" {
                await refreshCollectionEntries()
            } else {
                await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
            }
            guard isCurrentSession(context) else { return }
            if recipeId == "collection" {
                collectionHandshakeState = .ready
                collectionHandshakeContext = context
                await drainOfflineQueue(sessionContext: context)
            }
            return
        }

        var mergeSucceeded = false
        do {
            try await applyServerDocumentState(
                context: context,
                recipeId: recipeId,
                docKey: docKey,
                stateData: missingUpdate,
                lastSyncedAt: lastSyncedAt
            )
            mergeSucceeded = true
        } catch {
            logger.error("Failed to apply sync_step2 update for \(UserIdFormatter.redactDocKey(docKey)): \(error)")
        }
        guard isCurrentSession(context) else { return }

        if isRecipeDocument(recipeId: recipeId) {
            if mergeSucceeded {
                descriptionEditorSessions[recipeId]?.bridge?.applyRemoteUpdate(missingUpdate)
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
        guard isCurrentSession(context) else { return }
        if recipeId == "collection", mergeSucceeded {
            collectionHandshakeState = .ready
            collectionHandshakeContext = context
            await drainOfflineQueue(sessionContext: context)
        }
    }

    private func collectionIsTruncated(
        serverSummary: CollectionSyncSummary,
        docKey: String
    ) async -> Bool {
        guard let local = try? await documentManager.readCollectionStructure() else {
            return false
        }
        guard local.totalCount >= 0 else { return false }
        let missingLiveIds = serverSummary.liveRecipeIds.subtracting(local.liveRecipeIds)
            .subtracting(local.deletedRecipeIds)
        return !missingLiveIds.isEmpty
    }

    private func handleDocumentsLoaded(
        context: SyncSocketSessionContext,
        documents: [(String, Data, String?)]
    ) async {
        guard isCurrentSession(context) else { return }
        var shouldRefreshCollection = false
        var loadedRecipeIds: [String] = []
        if !documents.isEmpty { lastSuccessfulSyncAt = Date() }
        for (recipeId, stateData, lastSyncedAt) in documents {
            guard isCurrentSession(context) else { return }
            let docKey = docKeyFor(recipeId: recipeId, userId: context.userId)
            do {
                try await applyServerDocumentState(
                    context: context,
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
        guard isCurrentSession(context) else { return }
        if shouldRefreshCollection {
            await refreshCollectionEntries()
            guard isCurrentSession(context) else { return }
        }
        if documents.contains(where: { $0.0 == ShoppingListConstants.offlineRecipeId }) {
            await refreshShoppingSnapshot()
            guard isCurrentSession(context) else { return }
        }
        if !loadedRecipeIds.isEmpty {
            recipeBatchLoadCompleted += loadedRecipeIds.count
        }
        recipeBatchLoadInFlight = false
        recipeBatchLoadTotal = 0
        recipeBatchLoadCompleted = 0
        await refreshRecipeDocumentCacheStatus()
        guard isCurrentSession(context) else { return }
        if let active = activeRecipeId, loadedRecipeIds.contains(active) {
            await refreshCurrentRecipe(recipeId: active)
        }
    }

    /// Batch-fetch recipe Y.Docs missing from SQLite (web: `load_documents` after collection sync).
    private func scheduleRecipeDocumentsBatchLoad(recipeIds: [String]) {
        guard connectionState == .connected, isSocketAuthenticated else { return }
        guard socket?.status == .connected else { return }
        guard let sessionContext = currentSocketSessionContext else { return }
        recipeBatchLoadTask?.cancel()
        recipeBatchLoadTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.isCurrentSession(sessionContext) else { return }
            await self.emitRecipeDocumentsBatchLoad(
                recipeIds: recipeIds,
                sessionContext: sessionContext
            )
        }
    }

    private func emitRecipeDocumentsBatchLoad(
        recipeIds: [String],
        sessionContext: SyncSocketSessionContext? = nil
    ) async {
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        } else {
            guard connectionState == .connected, isSocketAuthenticated else { return }
            guard socket?.status == .connected else { return }
        }
        let missing = await recipeIdsMissingLocalSnapshots(
            recipeIds,
            userId: sessionContext?.userId
        )
        if let sessionContext {
            guard isCurrentSession(sessionContext) else { return }
        }
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
        if let sessionContext {
            guard isCurrentSession(sessionContext),
                  let client = socket,
                  isCurrentSession(sessionContext, client: client) else {
                return
            }
            client.emit("load_documents", ["recipeIds": missing])
        } else {
            guard let client = socket, client.status == .connected else {
                return
            }
            client.emit("load_documents", ["recipeIds": missing])
        }
        logger.info("Emitted load_documents for \(missing.count) recipes")
    }

    private func recipeIdsMissingLocalSnapshots(
        _ recipeIds: [String],
        userId: String? = nil
    ) async -> [String] {
        guard let userId = userId ?? self.userId, self.userId == userId else { return [] }
        let candidates = recipeIds.filter { isRecipeDocument(recipeId: $0) }
        let docKeys = candidates.map { docKeyFor(recipeId: $0, userId: userId) }
        guard !docKeys.isEmpty else { return [] }
        let existing = (try? await store.existingSnapshotKeys(docKeys: docKeys)) ?? []
        guard self.userId == userId else { return [] }
        return zip(candidates, docKeys)
            .compactMap { recipeId, docKey in existing.contains(docKey) ? nil : recipeId }
    }

    private func handleRecipeUpdated(
        context: SyncSocketSessionContext,
        recipeId: String,
        updateData: Data
    ) async {
        guard isCurrentSession(context) else { return }
        let docKey = docKeyFor(recipeId: recipeId, userId: context.userId)
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
            guard isCurrentSession(context) else { return }
            requestDocumentReload(recipeId: recipeId, context: context)
            return
        }

        guard isCurrentSession(context) else { return }
        descriptionEditorSessions[recipeId]?.bridge?.applyRemoteUpdate(updateData)
        await refreshCurrentRecipeIfAllowed(recipeId: recipeId)
    }

    private func handleCollectionUpdated(
        context: SyncSocketSessionContext,
        updateData: Data
    ) async {
        guard isCurrentSession(context) else { return }
        let collectionKey = docKeyFor(recipeId: "collection", userId: context.userId)
        logger.debug("collection_updated: \(updateData.count) bytes")

        do {
            try await documentManager.applyUpdate(key: collectionKey, data: updateData)
        } catch {
            logger.error("Failed to apply collection update: \(error)")
        }

        guard isCurrentSession(context) else { return }
        await refreshCollectionEntries()
    }

    /// Histogram of duplicate application ids in live collection entries.
    private static func duplicateIdSummary(
        _ entries: [CollectionEntry]
    ) -> (liveCount: Int, duplicateIdCount: Int, duplicateIds: String) {
        var counts: [String: Int] = [:]
        for entry in entries where !entry.deleted {
            counts[entry.id, default: 0] += 1
        }
        let dups = counts.filter { $0.value > 1 }.sorted { $0.key < $1.key }
        return (
            counts.values.reduce(0, +),
            dups.count,
            dups.prefix(5).map { "\($0.key)x\($0.value)" }.joined(separator: ",")
        )
    }

    private func handleShoppingListUpdated(
        context: SyncSocketSessionContext,
        updateData: Data
    ) async {
        guard isCurrentSession(context) else { return }
        let key = Self.shoppingDocKey(userId: context.userId)
        logger.debug("shopping_list_updated: \(updateData.count) bytes")
        lastSuccessfulSyncAt = Date()
        do {
            try await documentManager.applyUpdate(key: key, data: updateData)
        } catch {
            logger.error("Failed to apply shopping list update: \(error)")
        }
        guard isCurrentSession(context) else { return }
        await refreshShoppingSnapshot()
    }

    func refreshShoppingSnapshot() async {
        guard userId != nil else { return }
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
        _ = try? await documentManager.getOrCreateDoc(
            key: docKeyFor(recipeId: recipeId, userId: userId)
        )
        guard self.userId == userId else { return nil }
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
        let docKeys = entries.map { docKeyFor(recipeId: $0.id, userId: userId) }
        let existingKeys = (try? await store.existingSnapshotKeys(docKeys: docKeys)) ?? []
        guard self.userId == userId else { return }
        var cached = 0
        var pending: [RecipeDocumentCachePendingEntry] = []
        for entry in entries {
            let key = docKeyFor(recipeId: entry.id, userId: userId)
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
        let capturedContext = currentSocketSessionContext
        imageCacheStatusRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            if let capturedContext {
                guard let self, self.isCurrentSession(capturedContext) else { return }
            }
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
                Task { @MainActor [weak self] in
                    self?.scheduleImageCacheStatusRefresh()
                }
            }
        }
    }

    private func scheduleImagePrefetch(for entries: [CollectionEntry]) {
        let allowNetwork = connectionState == .connected
        let capturedContext = currentSocketSessionContext
        scheduleImageCacheStatusRefresh()
        Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            if let capturedContext {
                guard self.isCurrentSession(capturedContext) else { return }
            }
            await self.recipeImage.prefetchPreviews(
                entries: entries,
                allowNetwork: allowNetwork
            )
            guard !Task.isCancelled else { return }
            if let capturedContext {
                guard self.isCurrentSession(capturedContext) else { return }
            }
            await self.refreshImageCacheStatus()
        }
    }

    // MARK: - Collection Reading

    private func scheduleCollectionEntriesRefresh() {
        collectionEntriesRefreshTask?.cancel()
        let capturedContext = currentSocketSessionContext
        collectionEntriesRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            if let capturedContext {
                guard let self, self.isCurrentSession(capturedContext) else { return }
            }
            await self?.refreshCollectionEntries()
        }
    }

    private func refreshCollectionEntries() async {
        guard userId != nil else { return }
        do {
            let entries = try await documentManager.readCollectionEntries()
            let filtered = entries.filter { !$0.deleted }
            let dup = Self.duplicateIdSummary(filtered)
            if dup.duplicateIdCount > 0 {
                logger.warning(
                    "Collection has \(dup.duplicateIdCount) duplicate application id(s): \(dup.duplicateIds)"
                )
            }
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
              let recipe = currentRecipe,
              recipe.id == recipeId,
              let entry = collectionEntry(for: recipeId) else { return }
        currentRecipe = RecipeCollectionMerge.merged(recipe, with: entry)
    }

    // MARK: - Local Snapshot Loading

    private func loadLocalSnapshots() async {
        guard let userId else { return }
        await installChangeHandlersIfNeeded()
        let collectionKey = "\(userId):collection"

        await documentManager.applyOfflineQueueToLocalDocs(userId: userId)

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
        guard let context = currentSocketSessionContext else { return }
        await handleSyncError(context: context, code: code, message: message, recipeId: recipeId)
    }

    private func handleSyncError(
        context: SyncSocketSessionContext,
        code: SyncErrorCode,
        message: String,
        recipeId: String?
    ) async {
        guard isCurrentSession(context) else { return }
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
                clearInFlightOfflineTracking(forDocKey: docKeyFor(recipeId: recipeId, userId: context.userId))
            }

        case .recipeDeleted:
            guard let recipeId else { return }
            cancelPendingWork(forRecipeId: recipeId)
            if activeRecipeId == recipeId {
                currentRecipe = nil
                activeRecipeId = nil
                activeRecipeWasRemoved = true
            }
            clearInFlightOfflineTracking(forDocKey: docKeyFor(recipeId: recipeId, userId: context.userId))
            try? await store.deleteOfflineQueue(forDocKey: docKeyFor(recipeId: recipeId, userId: context.userId))
            guard isCurrentSession(context) else { return }
            writeSyncStates.removeValue(forKey: recipeId)
            await markRecipeSynced(recipeId)
            guard isCurrentSession(context) else { return }
            await refreshCollectionEntries()

        case .emptyUpdate, .invalidUpdate:
            if let recipeId {
                clearInFlightOfflineTracking(forDocKey: docKeyFor(recipeId: recipeId, userId: context.userId))
                requestDocumentReload(recipeId: recipeId, context: context)
            } else {
                hasRequestedCollectionLoad = false
                loadCollectionDocument()
            }

        case .truncatedCollection:
            // Spec 054: server detected hard-deletes + saturated SV. After the
            // Binary Yjs sync migration, plain reload via sync_step1 with the
            // live SV no-ops. Mirror web: drop local collection state and
            // re-handshake with an empty SV. Do not surface as a user-facing
            // error — this is an internal recovery signal.
            await recoverCollectionFromServer(context: context)

        case .generic:
            guard let recipeId else { return }
            let docKey = docKeyFor(recipeId: recipeId, userId: context.userId)
            delayedSyncErrorTask?.cancel()
            delayedSyncErrorTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled, self.isCurrentSession(context) else { return }
                guard self.delayedSyncErrorTask != nil else { return }
                self.clearInFlightOfflineTracking(forDocKey: docKey)
                self.requestDocumentReload(recipeId: recipeId, context: context)
            }
        }
    }

    private func requestDocumentReload(
        recipeId: String,
        context: SyncSocketSessionContext
    ) {
        guard isCurrentSession(context) else { return }
        if recipeId == "collection" {
            hasRequestedCollectionLoad = false
            loadCollectionDocument()
        } else {
            let docKey = docKeyFor(recipeId: recipeId, userId: context.userId)
            emitSyncStep1(
                recipeId: recipeId,
                docKey: docKey,
                documentKind: nil,
                sessionContext: context
            )
        }
    }

    private func reloadCollectionFromServer() {
        guard let context = currentSocketSessionContext,
              isCurrentSession(context) else { return }
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
        guard let context = currentSocketSessionContext,
              isCurrentSession(context) else { return }
        let userId = context.userId
        let collectionKey = "\(userId):collection"
        hasRequestedCollectionLoad = false
        hasRequestedShoppingLoad = false
        loadCollectionDocument()

        if let recipeId = activeRecipeId {
            let docKey = docKeyFor(recipeId: recipeId, userId: userId)
            emitSyncStep1(
                recipeId: recipeId,
                docKey: docKey,
                documentKind: nil,
                sessionContext: context
            )
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

    private func docKeyFor(recipeId: String, userId: String) -> String {
        if recipeId == "collection" {
            return "\(userId):collection"
        }
        if recipeId == ShoppingListConstants.offlineRecipeId {
            return Self.shoppingDocKey(userId: userId)
        }
        return "\(userId):recipe:\(recipeId)"
    }

    private func docKeyFor(recipeId: String) -> String {
        guard let userId else { return recipeId }
        return docKeyFor(recipeId: recipeId, userId: userId)
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
        await drainOfflineQueue(sessionContext: nil)
    }

    func test_handleSyncConfirmed(recipeId: String, lastSyncedAt: String?) async {
        guard let userId else { return }
        await handleSyncConfirmed(
            accountId: userId,
            recipeId: recipeId,
            lastSyncedAt: lastSyncedAt,
            isSessionValid: { self.userId == userId }
        )
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

    func test_docKeyFor(recipeId: String, userId: String) -> String {
        docKeyFor(recipeId: recipeId, userId: userId)
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
