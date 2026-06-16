import Combine
import SwiftUI
import RecipeScalerCore

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var authService = AuthService.shared
    @StateObject private var syncService: YjsSyncService
    @StateObject private var remindersService: RemindersSyncService
    @StateObject private var spotlightIndexer: SpotlightIndexer
    @State private var showSplash = true
    @State private var appTheme = AppThemePreference.current
    @State private var appLanguage = AppLanguagePreference.current
    @Environment(\.scenePhase) private var scenePhase
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("ui-testing")

    /// Debug: auto-authenticate on simulator
    private let debugUserId = "cfcd839f-56f2-4411-9632-7795b75f96d1"

    init() {
        let database: YrsDatabase
        do {
            database = try YrsDatabase()
        } catch {
            // Fallback to in-memory if on-disk DB is corrupted or write-protected.
            // App will function but snapshots won't persist across launches.
            YrsDatabase.logInitFailure(error)
            do {
                database = try YrsDatabase.makeInMemoryFallback()
            } catch {
                YrsDatabase.logInitFailure(error)
                fatalError("Cannot initialize local database: \(error)")
            }
        }
        let store = YDocStore(dbQueue: database.dbQueue)
        let mapStore = RemindersMapStore(dbQueue: database.dbQueue)
        let sync = YjsSyncService(store: store)
        _syncService = StateObject(wrappedValue: sync)
        _remindersService = StateObject(wrappedValue: RemindersSyncService(mapStore: mapStore))
        _spotlightIndexer = StateObject(wrappedValue: SpotlightIndexer(syncService: sync))
        // Sync APIClient credentials from SharedAuthStore so that Share/Action
        // extensions can configure the same client via App Group UserDefaults.
        if let sharedUserId = SharedAuthStore.userId {
            APIClient.shared.configure(userId: sharedUserId)
        }
        // #region agent log
        AgentSyncDebugLog.sync(
            location: "ContentView.init",
            message: "contentview_init",
            data: [:]
        )
        // #endregion
    }

    private var effectiveUserId: String? {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-DisableDebugAutoLogin=1") {
            return authService.userId
        }
        return debugUserId
        #else
        return authService.userId
        #endif
    }

    private var isAuthenticated: Bool {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-DisableDebugAutoLogin=1") {
            return authService.isAuthenticated
        }
        return true
        #else
        return authService.isAuthenticated
        #endif
    }

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
            } else if isAuthenticated {
                #if DEBUG
                if RecipeDescriptionFixture.showsPreview {
                    DescriptionFixturePreviewView()
                } else {
                    appShell(syncService: syncService)
                }
                #else
                appShell(syncService: syncService)
                #endif
            } else {
                AuthView()
            }
        }
        .task {
            #if DEBUG
            if isUITesting || DebugLaunchOptions.shouldSkipSplash {
                showSplash = false
                if ShoppingSmokeTest.shouldRun, let userId = effectiveUserId {
                    Task.detached { @MainActor in
                        await ShoppingSmokeTest.Launcher.launchIfNeeded(
                            syncService: syncService,
                            userId: userId
                        )
                    }
                }
                return
            }
            #else
            if isUITesting {
                showSplash = false
                return
            }
            #endif
            try? await Task.sleep(nanoseconds: 500_000_000)
            showSplash = false
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.rootContent)
        .environment(\.font, AppTypography.body)
        .preferredColorScheme(appTheme.colorScheme)
        .environment(\.locale, appLanguage.locale)
        .onReceive(
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in
            // Only mutate @State when theme/language actually changed. UserDefaults.didChangeNotification
            // fires on every defaults write (sync layer writes constantly), and an unconditional
            // reassignment thrashes the root view — re-creating the YjsSyncService and tearing down a
            // live socket on a ~30s cadence.
            let newTheme = AppThemePreference.current
            if newTheme != appTheme {
                appTheme = newTheme
                // #region agent log
                AgentSyncDebugLog.sync(
                    location: "ContentView.defaultsChanged",
                    message: "root_state_mutated",
                    data: ["field": "theme", "value": String(describing: newTheme)]
                )
                // #endregion
            }
            let newLanguage = AppLanguagePreference.current
            if newLanguage != appLanguage {
                appLanguage = newLanguage
                // #region agent log
                AgentSyncDebugLog.sync(
                    location: "ContentView.defaultsChanged",
                    message: "root_state_mutated",
                    data: ["field": "language", "value": newLanguage.rawValue]
                )
                // #endregion
            }
        }
        #if !targetEnvironment(simulator)
        .onChange(of: authService.isAuthenticated) { _, authenticated in
            if !authenticated {
                syncService.stop()
                Task { @MainActor in
                    spotlightIndexer.stop()
                    await spotlightIndexer.clearAll()
                }
            }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Persist, then drop the socket so suspended requests don't time out on resume.
                Task { await syncService.persistAll() }
                syncService.handleEnteredBackground()
            case .inactive:
                // Transient (app switcher, notification shade) — persist but keep the socket.
                Task { await syncService.persistAll() }
            case .active:
                TimerLiveActivityActionQueue.drainIfNeeded()
                ShoppingIntentDrainer.drainIfNeeded(syncService: syncService)
                syncService.handleEnteredForeground()
                Task { await remindersService.reconcileRemindersToUserSnapshot() }
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private func appShell(syncService: YjsSyncService) -> some View {
        AppShellView()
            .environmentObject(syncService)
            .environment(TimerManager.shared)
            .environmentObject(remindersService)
            .environmentObject(spotlightIndexer)
            .onAppear {
                installTimerLiveActivityRecipeLookup(syncService: syncService)
                TimerManager.shared.configure(modelContext: modelContext)
            }
            .task(id: effectiveUserId) {
                #if DEBUG
                if ShoppingSmokeTest.shouldRun { return }
                AgentSyncDebugLog.sync(
                    location: "ContentView.swift:appShell",
                    message: "app_shell_start",
                    data: ["userId": effectiveUserId ?? "nil"]
                )
                #endif
                if let userId = effectiveUserId {
                    await syncService.start(userId: userId)
                    remindersService.attach(to: syncService)
                    spotlightIndexer.start()
                    ShortcutItemsUpdater.update(from: syncService.collectionEntries)
                    RecipeSnapshotStore.save(syncService.collectionEntries)
                } else {
                    syncService.stop()
                    spotlightIndexer.stop()
                    await spotlightIndexer.clearAll()
                }
            }
            .onChange(of: syncService.collectionEntries) { _, entries in
                ShortcutItemsUpdater.update(from: entries)
                RecipeSnapshotStore.save(entries)
                installTimerLiveActivityRecipeLookup(syncService: syncService)
                TimerManager.shared.refreshLiveActivities()
            }
    }

    private func installTimerLiveActivityRecipeLookup(syncService: YjsSyncService) {
        TimerLiveActivityMetadataProvider.recipeNameLookup = { recipeId in
            syncService.collectionEntries
                .first(where: { $0.id == recipeId && !$0.deleted })?
                .name
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
