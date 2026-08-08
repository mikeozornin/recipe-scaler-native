import Combine
import SwiftUI
import SwiftData
import WidgetKit
import RecipeScalerCore

struct ContentView: View {
    @Environment(\.appContainer) private var container: AppContainer?
    @State private var showSplash = true
    @AppStorage(AppThemePreference.storageKey) private var appThemeRaw: String = AppThemePreference.system.rawValue
    @AppStorage(AppLanguagePreference.storageKey) private var appLanguageRaw: String?
    @Environment(\.scenePhase) private var scenePhase
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("ui-testing")

    private var appTheme: AppThemePreference {
        AppThemePreference(rawValue: appThemeRaw) ?? .system
    }

    /// Resolves the effective language preference. `@AppStorage` returns `nil`
    /// when the key has never been written — fall back to the system default
    /// (Russian system → `.ru`, otherwise → `.en`) so the locale matches what
    /// `AppLanguagePreference.bootstrap()` set up at launch.
    private var appLanguage: AppLanguagePreference {
        if let raw = appLanguageRaw, let value = AppLanguagePreference(rawValue: raw) {
            return value
        }
        return AppLanguagePreference.current
    }

    /// Debug: auto-authenticate on simulator. Debug-only — must never ship in
    /// Release. Guarded by `#if DEBUG` so the literal UUID is stripped from
    /// production binaries and the auto-login path is unreachable on device
    /// release builds. See review finding High #8.
    /// Credentials (userId + device_token) live in `DebugSimulatorAutoLogin`.
    #if DEBUG
    private var debugUserId: String { DebugSimulatorAutoLogin.userId }
    #endif

    /// Fallback construction for previews/tests when no AppContainer is in
    /// the environment. Returns nil in production (container is always present).
    private var syncService: YjsSyncService? { container?.sync }
    private var remindersService: RemindersSyncService? { container?.reminders }
    private var spotlightIndexer: SpotlightIndexer? { container?.spotlight }
    private var authService: AuthService? { container?.auth }

    private var effectiveUserId: String? {
        #if DEBUG
        #if targetEnvironment(simulator)
        // E2E UI tests inject a per-test fresh userId via launch env so each
        // test gets its own clean user (web parity: register-auto fixture).
        if let env = ProcessInfo.processInfo.environment["E2E_OVERRIDE_USER_ID"],
           !env.isEmpty {
            return env
        }
        if ProcessInfo.processInfo.arguments.contains("-DisableDebugAutoLogin=1") {
            return authService?.userId
        }
        return debugUserId
        #else
        return authService?.userId
        #endif
        #else
        return authService?.userId
        #endif
    }

    private var isAuthenticated: Bool {
        #if DEBUG
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["E2E_OVERRIDE_USER_ID"] != nil {
            return true
        }
        if ProcessInfo.processInfo.arguments.contains("-DisableDebugAutoLogin=1") {
            return authService?.isAuthenticated ?? false
        }
        return true
        #else
        return authService?.isAuthenticated ?? false
        #endif
        #else
        return authService?.isAuthenticated ?? false
        #endif
    }

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
            } else if isAuthenticated, let container {
                #if DEBUG
                if RecipeDescriptionFixture.showsPreview {
                    DescriptionFixturePreviewView()
                } else {
                    appShell(container: container)
                }
                #else
                appShell(container: container)
                #endif
            } else if container != nil {
                AuthView()
            } else {
                ProgressView()
            }
        }
        .task {
            #if DEBUG
            if isUITesting || DebugLaunchOptions.shouldSkipSplash {
                showSplash = false
                if ShoppingSmokeTest.shouldRun, let userId = effectiveUserId, let syncService {
                    Task.detached { @MainActor in
                        await ShoppingSmokeTest.Launcher.launchIfNeeded(
                            syncService: syncService,
                            userId: userId
                        )
                    }
                }
                if TimerNotificationSmokeTest.shouldRun, let container {
                    Task.detached { @MainActor in
                        TimerNotificationSmokeTest.Launcher.launchIfNeeded(timerManager: container.timer)
                    }
                }
                if let container,
                   DebugLaunchOptions.screenshotCapture
                    || DebugLaunchOptions.screenshotTimerSeconds != nil
                    || DebugLaunchOptions.screenshotShoppingSeed != nil {
                    Task.detached { @MainActor in
                        // Wait briefly so ActivityKit / LA auth is ready after cold launch.
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        DebugLaunchOptions.applyScreenshotTimerIfNeeded(timerManager: container.timer)
                        if DebugLaunchOptions.screenshotShoppingSeed != nil {
                            await DebugLaunchOptions.applyScreenshotShoppingSeedIfNeeded(
                                syncService: container.sync
                            )
                        }
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
        #if !targetEnvironment(simulator)
        .onChange(of: authService?.isAuthenticated ?? false) { _, authenticated in
            guard let container else { return }
            if !authenticated {
                Task { @MainActor in
                    await container.sync.clearSessionForLogout()
                    await container.stopForLogout()
                }
            }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            guard let container else { return }
            switch phase {
            case .background:
                // Persist, then drop the socket so suspended requests don't time out on resume.
                Task { await container.sync.persistAll() }
                container.sync.handleEnteredBackground()
                // Refresh Home/Lock Screen widgets with the latest timer snapshot
                // so the countdown stays correct while the app isn't foreground.
                WidgetCenter.shared.reloadAllTimelines()
            case .inactive:
                // Transient (app switcher, notification shade) — persist but keep the socket.
                Task { await container.sync.persistAll() }
            case .active:
                TimerLiveActivityActionQueue.drainIfNeeded()
                if let syncService {
                    ShoppingIntentDrainer.drainIfNeeded(syncService: syncService)
                    syncService.handleEnteredForeground()
                }
                // Spec 058: suppress progress LA sync, pull server timers (force),
                // then reconcile — so APNs pause is not overwritten by stale running.
                Task {
                    container.timer.beginForegroundRemoteRefresh()
                    await container.timerSync.loadActiveTimersFromServer(force: true)
                    container.timer.endForegroundRemoteRefresh()
                    await container.reminders.reconcileRemindersToUserSnapshot()
                }
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private func appShell(container: AppContainer) -> some View {
        Group {
            #if DEBUG
            if let sceneId = DebugLaunchOptions.openGuideMediaScene {
                GuideMediaStudioView(sceneId: sceneId)
            } else {
                AppShellView(coordinator: container.shellCoordinator)
            }
            #else
            AppShellView(coordinator: container.shellCoordinator)
            #endif
        }
        .task(id: effectiveUserId) {
            #if DEBUG
            if ShoppingSmokeTest.shouldRun { return }
            AgentSyncDebugLog.sync(
                location: "ContentView.swift:appShell",
                message: "app_shell_start",
                data: ["userId": UserIdFormatter.redact(effectiveUserId)]
            )
            #endif
            #if DEBUG
            if DebugLaunchOptions.openGuideMediaScene != nil { return }
            #endif
            if let userId = effectiveUserId {
                await container.bootstrap(userId: userId)
            } else {
                container.sync.stop()
                container.spotlight.stop()
                await container.spotlight.clearAll()
            }
        }
        .onChange(of: container.sync.collectionEntries) { _, entries in
            ShortcutItemsUpdater.update(from: entries)
            RecipeSnapshotStore.save(entries)
            TimerLiveActivityMetadataProvider.recipeNameLookup = { recipeId in
                entries.first(where: { $0.id == recipeId && !$0.deleted })?.name
            }
            container.timer.refreshLiveActivities()
            container.shellCoordinator.resolvePendingSpotlightRecipe(in: entries)
        }
    }
}

#Preview {
    let modelContainer = try! ModelContainer(for: RecipeTimer.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let container = try! AppContainer(modelContext: ModelContext(modelContainer))
    return ContentView()
        .appEnvironment(container)
        .modelContainer(for: RecipeTimer.self, inMemory: true)
}
