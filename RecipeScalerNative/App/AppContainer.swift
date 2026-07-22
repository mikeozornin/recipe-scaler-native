import Foundation
import SwiftUI
import SwiftData
import RecipeScalerCore

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
    /// `nonisolated(unsafe)` because the value is written exactly once during app
    /// startup on MainActor and never mutated afterward; reads from nonisolated
    /// contexts (actors, AppIntents) are safe — they only dereference a stable
    /// pointer to a fully-initialized object.
    nonisolated(unsafe) static var shared: AppContainer?

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
    /// Tab + nested navigation state; lives on the container so theme/locale root updates
    /// do not recreate paths when `AppShellView` is torn down.
    let shellCoordinator: AppShellCoordinator
    let timerLiveActivityCoordinator: TimerLiveActivityCoordinator

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
        self.timerLiveActivityCoordinator = TimerLiveActivityCoordinator()

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
            deepLinkRouter: deepLinkRouter
        )

        // Feature adoption store (spec 038). Cache is loaded lazily in
        // `bootstrap(userId:)` so the section renders instantly on first appear.
        self.featureAdoption = FeatureAdoptionStore()

        // Bridge the cyclic callback
        let bridge = TimerEventBridge()
        bridge.install(sync: sync, timerSync: timerSync)
        self.timerEventBridge = bridge

        // Bind process-wide handle for AppIntents + non-SwiftUI callers.
        Self.shared = self

        // Sync APIClient credentials from Keychain so Share/Action extensions
        // configuring the same client see the same identity at launch.
        if let sharedUserId = SharedAuthStore.userId {
            if let token = SharedAuthStore.token, !token.isEmpty {
                APIClient.shared.configure(authToken: token)
            }
            APIClient.shared.configure(userId: sharedUserId)
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

        // Spec 054: before anything else, verify the stored user still exists
        // on the server. If `/api/settings` 404s, wipe local credentials and
        // bail out — `ContentView` will fall back to `AuthView` because
        // `auth.isAuthenticated == false`. Runs once per cold start.
        if !didPerformStaleSessionHealthCheck {
            didPerformStaleSessionHealthCheck = true
            await auth.performStaleSessionHealthCheck()
            if !auth.isAuthenticated {
                // Wipe rewrote auth state; do not start sync/timer/socket for
                // a user that no longer exists. The next login will re-enter
                // `bootstrap(userId:)` with a fresh `userId`.
                return
            }
        }

        let isSameUser = bootstrappedUserId == userId
        if !isSameUser {
            shellCoordinator.resetShellStateForLogout()
        }
        bootstrappedUserId = userId

        // 0. Feature-adoption cache (spec 038). Synchronous read so the section
        //    renders from cache before any network resolves on this session.
        featureAdoption.loadFromCache()

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
        sync.stop()
        spotlight.stop()
        await spotlight.clearAll()
        featureAdoption.clearForLogout()
    }
}
