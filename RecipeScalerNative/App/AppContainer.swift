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
    let timerLiveActivityCoordinator: TimerLiveActivityCoordinator

    // MARK: - Networked services

    let auth: AuthService
    let pushSchedule: PushScheduleService
    let pushRegistration: PushRegistrationService
    let timerSync: TimerSyncService
    let timer: TimerManager
    let recipeImage: RecipeImageService

    // MARK: - Sync subsystem (depend on the services above)

    let sync: YjsSyncService
    let reminders: RemindersSyncService
    let spotlight: SpotlightIndexer

    /// Holds the cyclic `TimerSyncService.sendTimerEvent ↔ YjsSyncService.emitTimerEvent`
    /// callback so neither service retains the other directly.
    private let timerEventBridge: TimerEventBridge

    /// Captured at `bootstrap(userId:)` for re-runs (account switch, root view churn).
    private var bootstrappedUserId: String?

    // MARK: - Construction

    init(modelContext: ModelContext) throws {
        let database: YrsDatabase
        do {
            database = try YrsDatabase()
        } catch {
            YrsDatabase.logInitFailure(error)
            database = try YrsDatabase.makeInMemoryFallback()
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

        // Bridge the cyclic callback
        let bridge = TimerEventBridge()
        bridge.install(sync: sync, timerSync: timerSync)
        self.timerEventBridge = bridge

        // Bind process-wide handle for AppIntents + non-SwiftUI callers.
        Self.shared = self

        // Sync APIClient credentials from Keychain so Share/Action extensions
        // configuring the same client see the same identity at launch.
        if let sharedUserId = SharedAuthStore.userId {
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

        let isSameUser = bootstrappedUserId == userId
        bootstrappedUserId = userId

        // 1. Configure APIClient (formerly `ContentView.init:45` + `YjsSyncService.start:867`).
        APIClient.shared.configure(userId: userId)

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

    /// Stop sync + clear local state on logout (formerly `ContentView.onChange(of: authService.isAuthenticated)`).
    func stopForLogout() async {
        sync.stop()
        spotlight.stop()
        await spotlight.clearAll()
    }
}
