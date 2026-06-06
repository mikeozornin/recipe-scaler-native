import Combine
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var authService = AuthService.shared
    @StateObject private var syncService: YjsSyncService
    @StateObject private var remindersService: RemindersSyncService
    @State private var showSplash = true
    @State private var appTheme = AppThemePreference.current
    @State private var appLanguage = AppLanguagePreference.current
    @Environment(\.scenePhase) private var scenePhase
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("ui-testing")

    /// Debug: auto-authenticate on simulator
    private let debugUserId = "cfcd839f-56f2-4411-9632-7795b75f96d1"

    init() {
        let database = try! YrsDatabase()
        let store = YDocStore(dbQueue: database.dbQueue)
        let mapStore = RemindersMapStore(dbQueue: database.dbQueue)
        _syncService = StateObject(wrappedValue: YjsSyncService(store: store))
        _remindersService = StateObject(wrappedValue: RemindersSyncService(mapStore: mapStore))
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
        return debugUserId
        #else
        return authService.userId
        #endif
    }

    private var isAuthenticated: Bool {
        #if targetEnvironment(simulator)
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
            .environmentObject(TimerManager.shared)
            .environmentObject(remindersService)
            .onAppear {
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
                } else {
                    syncService.stop()
                }
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
