import Foundation
import SwiftUI
import SwiftData
import os
import RecipeScalerCore

#if os(macOS)
/// macOS composition root.
///
/// The object is still `AppContainer` (not a second container): the target
/// omits iOS-only extensions, Live Activities and widget/reminder chrome while
/// keeping the same auth, Yjs, image-cache, timer-sync and shell lifecycles.
@MainActor
@Observable
final class AppContainer {
    nonisolated static var shared: AppContainer? {
        sharedLock.withLock { $0 }
    }

    nonisolated static func setShared(_ container: AppContainer?) {
        sharedLock.withLock { $0 = container }
    }

    private nonisolated static let sharedLock = OSAllocatedUnfairLock<AppContainer?>(initialState: nil)

    let database: YrsDatabase
    let store: YDocStore
    let mapStore: RemindersMapStore

    let imageCache: ImageCacheService
    let publicImageCache: PublicImageCacheService
    let yjsMergeHelper: YjsMergeHelper
    let assistantRecipeContext: AssistantRecipeContext
    let deepLinkRouter: DeepLinkRouter
    let discoverListState: DiscoverListStateStore
    let shellCoordinator: AppShellCoordinator

    let auth: AuthService
    let pushSchedule: PushScheduleService
    let pushRegistration: PushRegistrationService
    let timerSync: TimerSyncService
    let timer: TimerManager
    let recipeImage: RecipeImageService
    let api: APIClient = .shared
    let sync: YjsSyncService

    private let timerEventBridge: TimerEventBridge
    private var bootstrappedUserId: String?

    init(modelContext: ModelContext) throws {
        let database: YrsDatabase
        let isTestingHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("ui-testing")
        if isTestingHost {
            database = try YrsDatabase.makeInMemoryForTesting()
        } else {
            do {
                database = try YrsDatabase()
            } catch {
                YrsDatabase.logInitFailure(error)
                database = try YrsDatabase.makeInMemoryFallback()
            }
        }
        self.database = database
        self.store = YDocStore(dbQueue: database.dbQueue)
        self.mapStore = RemindersMapStore(dbQueue: database.dbQueue)

        let imageCache = ImageCacheService()
        self.imageCache = imageCache
        let publicImageCache = PublicImageCacheService()
        self.publicImageCache = publicImageCache
        let yjsMergeHelper = YjsMergeHelper()
        self.yjsMergeHelper = yjsMergeHelper
        self.assistantRecipeContext = AssistantRecipeContext()
        let deepLinkRouter = DeepLinkRouter()
        self.deepLinkRouter = deepLinkRouter
        let discoverListState = DiscoverListStateStore()
        self.discoverListState = discoverListState

        let auth = AuthService()
        self.auth = auth
        let pushSchedule = PushScheduleService()
        self.pushSchedule = pushSchedule
        let pushRegistration = PushRegistrationService(auth: auth)
        self.pushRegistration = pushRegistration
        let timerSync = TimerSyncService()
        self.timerSync = timerSync
        let timer = TimerManager(timerSync: timerSync, modelContext: modelContext)
        self.timer = timer
        let recipeImage = RecipeImageService(
            imageCache: imageCache,
            publicImageCache: publicImageCache
        )
        self.recipeImage = recipeImage

        let sync = YjsSyncService(
            store: store,
            timerSync: timerSync,
            pushRegistration: pushRegistration,
            recipeImage: recipeImage,
            yjsMergeHelper: yjsMergeHelper
        )
        self.sync = sync
        self.shellCoordinator = AppShellCoordinator(
            syncService: sync,
            deepLinkRouter: deepLinkRouter,
            fileImportCoordinator: nil,
            discoverListState: discoverListState
        )

        let fileImportCoordinator = RecipeFileImportCoordinator(syncService: sync)
        fileImportCoordinator.shellCoordinator = shellCoordinator
        shellCoordinator.fileImportCoordinator = fileImportCoordinator

        let bridge = TimerEventBridge()
        bridge.install(sync: sync, timerSync: timerSync)
        self.timerEventBridge = bridge

        Self.setShared(self)
        if let sharedUserId = SharedAuthStore.userId {
            if let token = SharedAuthStore.token, !token.isEmpty {
                api.configure(authToken: token)
            }
            api.configure(userId: sharedUserId)
        }

        APIClient.shared.unauthorizedHandler = { [weak self] in
            await Task { @MainActor in
                await self?.auth.handleDeviceTokenInvalid()
            }.value
        }
        sync.authInvalidationHandler = { [weak self] reason in
            await Task { @MainActor in
                await self?.auth.handleAccountDeleted(reason: reason)
            }.value
        }
        auth.performContainerTeardown = { [weak self] reason, bearer, userId in
            await self?.performInvalidationTeardown(
                wipeReason: reason,
                bearerForUnregister: bearer,
                userIdForUnregister: userId
            )
        }
    }

    func bootstrap(userId: String) async {
        let isTestingHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("ui-testing")
        if isTestingHost { return }

        let isSameUser = bootstrappedUserId == userId
        if !isSameUser, bootstrappedUserId != nil {
            shellCoordinator.resetShellStateForLogout()
            discoverListState.clearAll()
        }
        bootstrappedUserId = userId

        if auth.userId == nil {
            auth.userId = userId
            auth.isAuthenticated = true
        }
        SharedAuthStore.userId = userId
        await auth.ensureDeviceTokenMigratedIfNeeded()
        api.configure(authToken: SharedAuthStore.token ?? auth.token)
        api.configure(userId: userId)
        timerSync.configure(
            userId: userId,
            deviceId: TimerSyncService.storedDeviceId(),
            timerManager: timer
        )

        // Keep the image cache lifecycle in the composition root on macOS too.
        // `YjsSyncService.start` intentionally no longer installs observers.
        sync.installImageCacheObserversIfNeeded()

        if isSameUser {
            await sync.resumeSession(userId: userId)
        } else {
            await sync.start(userId: userId)
        }
    }

    func resetBootstrapAfterLogout() {
        bootstrappedUserId = nil
    }

    func stopForLogout() async {
        resetBootstrapAfterLogout()
        shellCoordinator.resetShellStateForLogout()
        discoverListState.clearAll()
        await sync.clearSessionForLogout()
        sync.stop()
    }

    func performInvalidationTeardown(
        wipeReason: SessionWipeReason,
        bearerForUnregister: String?,
        userIdForUnregister: String?
    ) async {
        _ = wipeReason
        if let bearerForUnregister, !bearerForUnregister.isEmpty {
            api.configure(authToken: bearerForUnregister)
        }
        if let userIdForUnregister, !userIdForUnregister.isEmpty {
            api.configure(userId: userIdForUnregister)
        }
        await stopForLogout()
    }
}
#else
/// Single source of truth for all app-level services.
///
/// Built once in `RecipeScalerNativeApp.init`. Services are constructed in dependency
/// order with explicit `init(...)` parameters — no hidden cross-singleton wiring.
///
/// `bootstrap(userId:)` runs the wiring that previously lived inside
/// `YjsSyncService.start` (lines 856-884) and `ContentView.appShell.onAppear`.
///
/// AppIntents and other non-SwiftUI callers access the container via
/// `AppContainer.shared`. SwiftUI views access it via `@Environment(AppContainer.self)`
/// (or per-service `@Environment` declared in `AppEnvironment.swift`).
@MainActor
@Observable
final class AppContainer {
    /// Process-wide handle. Set once by `RecipeScalerNativeApp.init`; AppIntents read
    /// from it because they cannot use `@Environment`. View code should prefer the
    /// `@Environment(AppContainer.self)` route injected at `WindowGroup`.
    ///
    /// Backed by `OSAllocatedUnfairLock` so reads from nonisolated contexts
    /// (actors, AppIntents, APNs callbacks) are race-free even though they
    /// happen off the MainActor. The value is written exactly once during app
    /// startup and never mutated afterward, but the lock still protects
    /// against the read/write race that `nonisolated(unsafe)` would allow
    /// under Thread Sanitizer and on weak memory models.
    nonisolated static var shared: AppContainer? {
        sharedLock.withLock { $0 }
    }

    /// Internal setter kept nonisolated so `RecipeScalerNativeApp.init` (which is
    /// MainActor) can install the value without hopping. The lock serializes
    /// the write against any concurrent reader.
    nonisolated static func setShared(_ container: AppContainer?) {
        sharedLock.withLock { $0 = container }
    }

    /// Lock-protected storage. `OSAllocatedUnfairLock` is a value type that owns
    /// its heap storage; the lock guards a single optional `AppContainer`
    /// reference. Callers that dereference the returned container are
    /// responsible for hopping to the MainActor before touching the
    /// container's state.
    private nonisolated static let sharedLock = OSAllocatedUnfairLock<AppContainer?>(initialState: nil)

    // MARK: - Foundation

    let database: YrsDatabase
    let store: YDocStore
    let mapStore: RemindersMapStore

    // MARK: - Leaf services (no project deps)

    let imageCache: ImageCacheService
    let publicImageCache: PublicImageCacheService
    let yjsMergeHelper: YjsMergeHelper
    let assistantRecipeContext: AssistantRecipeContext
    let deepLinkRouter: DeepLinkRouter
    let discoverListState: DiscoverListStateStore
    /// Tab + nested navigation state; lives on the container so theme/locale root updates
    /// do not recreate paths when `AppShellView` is torn down.
    let shellCoordinator: AppShellCoordinator
    let timerLiveActivityCoordinator: TimerLiveActivityCoordinator
    let liveActivityPushRegistrar: LiveActivityPushRegistrar
    /// Spec 030 B2 — widget push token register/unregister (composition-root only).
    let widgetPushRegistrar: WidgetPushRegistrar

    // MARK: - Networked services

    let auth: AuthService
    let pushSchedule: PushScheduleService
    let pushRegistration: PushRegistrationService
    let timerSync: TimerSyncService
    let timer: TimerManager
    let recipeImage: RecipeImageService
    let avatar: AvatarImageService

    /// Typed handle to the shared HTTP client. Exposed so view models and feature
    /// services can call the API without reaching for the `APIClient.shared`
    /// singleton (which is reserved for AppIntents / extensions / pre-bootstrap).
    let api: APIClient = .shared

    // MARK: - Sync subsystem (depend on the services above)

    let sync: YjsSyncService
    let reminders: RemindersSyncService
    let spotlight: SpotlightIndexer

    // MARK: - Feature adoption (spec 038)

    let featureAdoption: FeatureAdoptionStore

    // MARK: - System banner (spec 061)

    let systemBanner: SystemBannerStore

    // MARK: - App Store support

    /// StoreKit transactions belong to the Apple account, so this service is
    /// intentionally app-scoped and is not cleared when the Recipe Scaler
    /// account logs out.
    let tips: TipPurchaseService

    /// Holds the cyclic `TimerSyncService.sendTimerEvent ↔ YjsSyncService.emitTimerEvent`
    /// callback so neither service retains the other directly.
    private let timerEventBridge: TimerEventBridge

    /// Captured at `bootstrap(userId:)` for re-runs (account switch, root view churn).
    private var bootstrappedUserId: String?

    /// Spec 054: one-shot gate so the stale-session health-check runs at most
    /// once per cold start, not on every `bootstrap(userId:)` re-entry.
    private var didPerformStaleSessionHealthCheck = false

    // MARK: - Construction

    init(modelContext: ModelContext) throws {
        let database: YrsDatabase
        // Under XCTest/UI-test hosts we don't need on-disk persistence (each test
        // builds its own `YDocStore.inMemory()`), and the test host's sandbox often
        // carries stale schema from previous runs that triggers the slow fallback
        // path AND the "Local storage unavailable" banner. Skip straight to the
        // in-memory DB in that case — mirrors `bootstrap(userId:)`'s gate.
        let isTestingHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("ui-testing")
        if isTestingHost {
            database = try YrsDatabase.makeInMemoryForTesting()
        } else {
            do {
                database = try YrsDatabase()
            } catch {
                YrsDatabase.logInitFailure(error)
                database = try YrsDatabase.makeInMemoryFallback()
            }
        }
        self.database = database
        self.store = YDocStore(dbQueue: database.dbQueue)
        self.mapStore = RemindersMapStore(dbQueue: database.dbQueue)

        // Leaves
        self.imageCache = ImageCacheService()
        self.publicImageCache = PublicImageCacheService()
        self.yjsMergeHelper = YjsMergeHelper()
        self.assistantRecipeContext = AssistantRecipeContext()
        self.deepLinkRouter = DeepLinkRouter()
        let discoverListState = DiscoverListStateStore()
        self.discoverListState = discoverListState
        let liveActivityPushRegistrar = LiveActivityPushRegistrar()
        self.liveActivityPushRegistrar = liveActivityPushRegistrar
        self.timerLiveActivityCoordinator = TimerLiveActivityCoordinator(
            pushRegistrar: liveActivityPushRegistrar
        )
        self.widgetPushRegistrar = WidgetPushRegistrar()

        // Networked (authConfigured from Keychain by AuthService.init)
        let auth = AuthService()
        self.auth = auth
        self.pushSchedule = PushScheduleService()
        self.pushRegistration = PushRegistrationService(auth: auth)
        let timerSync = TimerSyncService()
        self.timerSync = timerSync
        self.timer = TimerManager(
            timerSync: timerSync,
            liveActivity: timerLiveActivityCoordinator,
            pushSchedule: pushSchedule,
            modelContext: modelContext
        )
        self.recipeImage = RecipeImageService(
            imageCache: imageCache,
            publicImageCache: publicImageCache
        )
        self.avatar = AvatarImageService(api: APIClient.shared)

        // Sync subsystem
        let sync = YjsSyncService(
            store: store,
            timerSync: timerSync,
            pushRegistration: pushRegistration,
            recipeImage: recipeImage,
            yjsMergeHelper: yjsMergeHelper
        )
        self.sync = sync
        self.reminders = RemindersSyncService(mapStore: mapStore)
        self.spotlight = SpotlightIndexer(syncService: sync)
        self.shellCoordinator = AppShellCoordinator(
            syncService: sync,
            deepLinkRouter: deepLinkRouter,
            fileImportCoordinator: nil,
            discoverListState: discoverListState
        )

        // Spec 057: silent `.recipe` importer for AirDrop / Files / Mail.
        // Built in the composition root (AGENTS.md: "all app-level services are
        // constructed in AppContainer") with its `weak` back-reference to the
        // shell coordinator wired immediately after construction.
        let fileImportCoordinator = RecipeFileImportCoordinator(syncService: sync)
        fileImportCoordinator.shellCoordinator = shellCoordinator
        shellCoordinator.fileImportCoordinator = fileImportCoordinator

        // Feature adoption store (spec 038). Cache is loaded lazily in
        // `bootstrap(userId:)` so the section renders instantly on first appear.
        self.featureAdoption = FeatureAdoptionStore()

        // System banner store (spec 061). Refreshed once per session during
        // bootstrap; never polls. Dismissal is persisted server-side.
        self.systemBanner = SystemBannerStore()

        // StoreKit support purchases are independent of the signed-in
        // Recipe Scaler account and must survive account switching.
        self.tips = TipPurchaseService()

        // Bridge the cyclic callback
        let bridge = TimerEventBridge()
        bridge.install(sync: sync, timerSync: timerSync)
        self.timerEventBridge = bridge

        // Bind process-wide handle for AppIntents + non-SwiftUI callers.
        Self.setShared(self)

        // Sync APIClient credentials from Keychain so Share/Action extensions
        // configuring the same client see the same identity at launch.
        if let sharedUserId = SharedAuthStore.userId {
            if let token = SharedAuthStore.token, !token.isEmpty {
                APIClient.shared.configure(authToken: token)
            }
            APIClient.shared.configure(userId: sharedUserId)
        }

        // Spec 055 Phase R: wire central auth-invalidation interceptors.
        // `APIClient.unauthorizedHandler` fires on any authenticated REST 401;
        // `sync.authInvalidationHandler` fires on socket `auth_error` with
        // `message == "Account deleted"`. Both delegate to `AuthService`,
        // which owns the re-entry-guarded wipe + teardown flow. Extensions do
        // NOT install these handlers — they must not wipe the session.
        //
        // Captures `[weak self]` (the container) instead of `[weak auth]` so
        // the closures can reach the container directly without routing
        // through `AppContainer.shared` — review finding C1/H6. The container
        // is always initialized before either handler can fire (handlers are
        // installed at the very end of `init`, after `sync` and `auth` are
        // fully constructed), eliminating the bootstrap-ordering race where
        // a 401 / socket `auth_error` arriving during early startup would
        // dereference a still-nil `AppContainer.shared`.
        //
        // The closures hop to `MainActor` themselves via `Task { @MainActor in }`
        // because `APIClient` is `nonisolated` and may call the handler from
        // any thread. AuthService is `@MainActor`, so the body runs there.
        APIClient.shared.unauthorizedHandler = { [weak self] in
            await Task { @MainActor in
                await self?.auth.handleDeviceTokenInvalid()
            }.value
        }
        sync.authInvalidationHandler = { [weak self] reason in
            await Task { @MainActor in
                await self?.auth.handleAccountDeleted(reason: reason)
            }.value
        }

        // Spec 055 Phase R (review finding C1): give AuthService a direct
        // handle to the container's teardown path so it no longer reaches back
        // through `AppContainer.shared`. The closure captures `[weak self]`;
        // when the container is deallocated (impossible in production but
        // possible in tests) the wipe still clears local state.
        auth.performContainerTeardown = { [weak self] reason, bearer, userId in
            await self?.performInvalidationTeardown(
                wipeReason: reason,
                bearerForUnregister: bearer,
                userIdForUnregister: userId
            )
        }
        auth.featureAdoptionStoreProvider = { [weak self] in
            self?.featureAdoption
        }

        AgentSyncDebugLog.sync(
            location: "AppContainer.init",
            message: "container_constructed",
            data: [:]
        )
    }

    // MARK: - Bootstrap

    /// Runs the wiring that previously lived inside `YjsSyncService.start`
    /// (lines 856-884) + `ContentView.appShell.onAppear`. Idempotent on the
    /// same userId; safe to call on every root-view churn.
    func bootstrap(userId: String) async {
        // Test host gate: when XCTest loads the app as TEST_HOST, do NOT start
        // the live sync/socket/push/spotlight stack — it parks the main thread
        // on socket auth ack (debug auto-login → `recipe-scaler.ru`) and the
        // XCTest watchdog kills the process before any test case runs
        // (`Test crashed with signal kill`, `Executed 0 tests`). Mirrors the
        // existing gate in `AuthService.init` (line ~114) and the 2 already-
        // `XCTSkipIf`-gated tests in `RecipeScalerNativeTests.swift:1271-1277`.
        // Audit of 39 test files confirmed: no test relies on a pre-started
        // sync session — see review finding #71.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isUITesting = ProcessInfo.processInfo.arguments.contains("ui-testing")
        if isTesting || isUITesting {
            return
        }

        // E2E UI tests inject a per-test fresh user via launch env so each
        // test runs in isolation (web parity: register-auto fixture).
        // Override SharedAuthStore + AuthService before any other bootstrap
        // step reads them so socket handshake, REST calls and exchange all
        // use the test-injected credentials.
        //
        // Guarded by `#if DEBUG` so a Release build cannot be impersonated by
        // any process that can set launch env (MDM, debugger-attached
        // processes, `xcrun simctl launch` on shared devices, share-extension
        // co-processes). See review finding Critical #1.
        #if DEBUG
        if let envUserId = ProcessInfo.processInfo.environment["E2E_OVERRIDE_USER_ID"],
           let envToken = ProcessInfo.processInfo.environment["E2E_OVERRIDE_DEVICE_TOKEN"],
           !envUserId.isEmpty, !envToken.isEmpty {
            SharedAuthStore.userId = envUserId
            SharedAuthStore.token = envToken
            auth.userId = envUserId
            auth.token = envToken
            auth.isAuthenticated = true
            APIClient.shared.configure(authToken: envToken)
            APIClient.shared.configure(userId: envUserId)
            // Skip stale-session health check for E2E — freshly-registered
            // user is guaranteed to exist on the server.
            didPerformStaleSessionHealthCheck = true
        }
        // DEBUG simulator auto-login is applied in `AuthService.init` (H3) so
        // credentials exist before bootstrap / other services read `userId`.
        // Post-wipe recovery below still re-exchanges via
        // `applyDebugSimulatorAutoLoginCredentials(preferBundledToken: false)`.
        #endif

        // Spec 054: before anything else, verify the stored user still exists
        // on the server. If `/api/settings` 404s, wipe local credentials and
        // bail out — `ContentView` will fall back to `AuthView` because
        // `auth.isAuthenticated == false`. Runs once per cold start.
        if !didPerformStaleSessionHealthCheck {
            didPerformStaleSessionHealthCheck = true
            await auth.performStaleSessionHealthCheck()
            if !auth.isAuthenticated {
                // Wipe rewrote auth state. On device, stop here so ContentView
                // shows AuthView and the next login re-enters bootstrap.
                //
                // Simulator DEBUG auto-login forces `ContentView.isAuthenticated`
                // and a hardcoded `debugUserId`, so AuthView never appears and
                // `.task(id:)` does not re-fire after wipe. Re-inject Bearer via
                // seed exchange, then fall through so sync.start binds the user.
                #if DEBUG
                if DebugSimulatorAutoLogin.isEnabled {
                    AppLog.info(.app, "stale_session_sim_debug_continue", data: [
                        "userId": UserIdFormatter.redact(userId)
                    ])
                    await applyDebugSimulatorAutoLoginCredentials(preferBundledToken: false)
                } else {
                    return
                }
                #else
                return
                #endif
            }
        }

        // Spec 059 fix: do NOT reset shell navigation state on the very first
        // bootstrap of a process. On cold launch with a Universal Link, iOS
        // delivers the URL before `container.bootstrap(userId:)` runs; by the
        // time `bootstrap` executes, the coordinator has already appended the
        // UL routes to `discoverPath`. The original logic treated `nil → userId`
        // as "user switched" and called `resetShellStateForLogout()`, wiping
        // the pending deep-link navigation. Reset only when we actually switch
        // between two different real user ids (post-initial bootstrap).
        let previousUserId = bootstrappedUserId
        let isSameUser = previousUserId == userId
        if !isSameUser, previousUserId != nil {
            shellCoordinator.resetShellStateForLogout()
            discoverListState.clearAll()
        }
        bootstrappedUserId = userId

        // 0. Feature-adoption cache (spec 038). Synchronous read so the section
        //    renders from cache before any network resolves on this session.
        featureAdoption.loadFromCache()

        // 0. System banner (spec 061). Synchronous cache load (no-op today).
        //    Network refresh runs after APIClient is configured (step 1) so the
        //    request carries Bearer / userId.
        systemBanner.loadFromCache()

        // 0a. Keep AuthService in sync with the active session. On simulator
        //     DEBUG builds, `ContentView.effectiveUserId` returns a hardcoded
        //     `debugUserId` and feeds it directly to `bootstrap(userId:)`,
        //     bypassing the Keychain-backed `AuthService` path. Without this
        //     reconciliation, `AuthService.shared.userId` stays `nil` and any
        //     code that reads it (e.g. `AccountSettingsViewModel.refresh`)
        //     early-returns, so the Account screen never loads sharing/profile.
        if auth.userId == nil {
            auth.userId = userId
            auth.isAuthenticated = true
        }

        // 0b. Spec 041: mirror userId before migration. DEBUG simulator passes
        //     `debugUserId` into bootstrap without `loginWithSeed`; exchange needs
        //     `SharedAuthStore.userId` + seed in Keychain. Run before sync so Socket.IO
        //     can handshake with Bearer when migration succeeds.
        SharedAuthStore.userId = userId
        await auth.ensureDeviceTokenMigratedIfNeeded()

        // 1. Configure APIClient (formerly `ContentView.init:45` + `YjsSyncService.start:867`).
        if let token = SharedAuthStore.token, !token.isEmpty {
            APIClient.shared.configure(authToken: token)
        } else if let authToken = auth.token, !authToken.isEmpty {
            APIClient.shared.configure(authToken: authToken)
        } else {
            APIClient.shared.configure(authToken: nil)
        }
        APIClient.shared.configure(userId: userId)

        // Spec 061: refresh after APIClient has Bearer / userId.
        Task { await systemBanner.refresh() }

        // 1a. Mirror session to paired watch (token may have been set by migration).
        WatchCredentialsBridge.shared.publish(userId: userId, token: SharedAuthStore.token)

        // 2. Configure TimerSync (formerly `YjsSyncService.start:868-872`). The
        //    `sendTimerEvent` callback is already wired by `TimerEventBridge`
        //    at construction time; no per-bootstrap assignment needed.
        timerSync.configure(
            userId: userId,
            deviceId: TimerSyncService.storedDeviceId(),
            timerManager: timer
        )

        // 3. Install image-cache observers (formerly `YjsSyncService.start:876`).
        sync.installImageCacheObserversIfNeeded()

        // 4. Install Live Activity recipe-name lookup (formerly `ContentView:229-233`).
        TimerLiveActivityMetadataProvider.recipeNameLookup = { [weak self] recipeId in
            self?.sync.collectionEntries
                .first(where: { $0.id == recipeId && !$0.deleted })?
                .name
        }

        // 5. Start the Yjs sync (formerly `ContentView.task:209`). `sync.start`
        //    no longer mutates other singletons — all side-effects live here.
        if isSameUser {
            await sync.resumeSession(userId: userId)
        } else {
            await sync.start(userId: userId)
        }

        // 6. Attach Reminders (formerly `ContentView.task:210`).
        reminders.attach(to: sync)

        // 7. Spotlight (formerly `ContentView.task:211`).
        spotlight.start()

        // 8. Mirror collection entries → Home Screen Quick Actions + snapshot store
        //    (formerly `ContentView.task:212-213`).
        ShortcutItemsUpdater.update(from: sync.collectionEntries)
        RecipeSnapshotStore.save(sync.collectionEntries)

        // 9. Spec 030 B2 — re-POST widget push token if the widget extension
        //    already cached one before this process bootstrapped (typical on
        //    cold launch with a widget on the Home Screen). Without this call,
        //    `WidgetPushRegistrar` is constructed in the container but never
        //    invoked from production code, leaving the entire B2 register layer
        //    as dead scaffolding. Code review 2026-08-05, finding #5.
        //    Fire-and-forget: registration failure is logged inside the registrar
        //    and retried on the next bootstrap.
        Task { [widgetPushRegistrar] in
            await widgetPushRegistrar.registerCachedIfNeeded()
        }
    }

    /// Clears bootstrap bookkeeping so the next login runs full `sync.start`, not `resumeSession`.
    func resetBootstrapAfterLogout() {
        bootstrappedUserId = nil
        // Spec 054: a fresh login after a wipe should re-probe on next bootstrap.
        didPerformStaleSessionHealthCheck = false
    }

    /// Stop sync + clear local state on logout (formerly `ContentView.onChange(of: authService.isAuthenticated)`).
    func stopForLogout() async {
        resetBootstrapAfterLogout()
        shellCoordinator.resetShellStateForLogout()
        discoverListState.clearAll()
        sync.stop()
        spotlight.stop()
        await spotlight.clearAll()
        // Spec 055/058: end Live Activities + wipe cached push tokens so the
        // Lock Screen and UserDefaults cannot leak the previous user's timers.
        await timerLiveActivityCoordinator.clearForLogout()
        // Spec 030 B2: drop widget push registration on logout.
        await widgetPushRegistrar.unregister()
        featureAdoption.clearForLogout()
        systemBanner.clearForLogout()
    }

    /// Spec 055 Phase R: full teardown after `AuthService` decides the local
    /// session should be wiped (cold-start stale-session probe, runtime
    /// account-deleted signal from socket, REST 401 with `User not found`,
    /// or explicit `deleteAccount`). Single source of truth for everything
    /// `AuthService` previously did by reaching back into `AppContainer.shared`.
    ///
    /// Captured credentials (`bearerForUnregister` / `userIdForUnregister`)
    /// are passed in by the caller because the Keychain wipe must happen on
    /// the AuthService side before this method runs — by the time we get
    /// here, `SharedAuthStore` is already empty.
    ///
    /// Idempotent: every sub-step is safe to call repeatedly (Live Activity
    /// coordinator, widget registrar, sync.clearSessionForLogout,
    /// stopForLogout all handle being called more than once).
    func performInvalidationTeardown(
        wipeReason: SessionWipeReason,
        bearerForUnregister: String?,
        userIdForUnregister: String?
    ) async {
        // Restore credentials onto APIClient for the unregister call only —
        // AuthService has already wiped SharedAuthStore/Keychain by this point.
        if let bearerForUnregister, !bearerForUnregister.isEmpty {
            APIClient.shared.configure(authToken: bearerForUnregister)
        }
        if let userIdForUnregister, !userIdForUnregister.isEmpty {
            APIClient.shared.configure(userId: userIdForUnregister)
        }
        await sync.clearSessionForLogout()
        await stopForLogout()
        // stopForLogout already covers timerLiveActivityCoordinator + widgetPushRegistrar
        // for the "stop everything" path; the per-step calls below mirror the
        // previous AuthService-only flow in case stopForLogout changes shape.
        _ = wipeReason
    }

    #if DEBUG
    /// Post-wipe DEBUG simulator recovery: re-exchanges the documented debug
    /// seed (or falls back to the bundled token) after a stale-session wipe.
    /// Cold-start inject lives in `AuthService.applyDebugSimulatorAutoLoginOnLaunchIfNeeded`
    /// so credentials exist before bootstrap (architecture review H3).
    private func applyDebugSimulatorAutoLoginCredentials(preferBundledToken: Bool) async {
        let userId = DebugSimulatorAutoLogin.userId
        let seed = DebugSimulatorAutoLogin.seedPhrase
        let env = ProcessInfo.processInfo.environment
        let launchToken = ["DEBUG_DEVICE_TOKEN", "E2E_OVERRIDE_DEVICE_TOKEN"]
            .compactMap { env[$0] }
            .first { !$0.isEmpty }

        let token: String
        if let launchToken {
            token = launchToken
        } else if preferBundledToken,
                  let existing = SharedAuthStore.token,
                  !existing.isEmpty,
                  SharedAuthStore.userId == userId {
            token = existing
        } else if preferBundledToken {
            token = DebugSimulatorAutoLogin.deviceToken
        } else {
            do {
                token = try await auth.exchangeSeedForToken(seedPhrase: seed)
                AppLog.info(.app, "debug_autologin_token_exchanged")
            } catch {
                AppLog.info(.app, "debug_autologin_token_exchange_failed", data: [
                    "reason": String(describing: type(of: error)),
                ])
                token = DebugSimulatorAutoLogin.deviceToken
            }
        }

        auth.applyDebugSimulatorSession(
            userId: userId,
            deviceToken: token,
            seedPhrase: seed
        )
        AppLog.info(.app, "debug_autologin_credentials_injected", data: [
            "userId": UserIdFormatter.redact(userId),
            "phase": preferBundledToken ? "bootstrap" : "stale_wipe_recovery",
        ])
    }
    #endif
}
#endif
