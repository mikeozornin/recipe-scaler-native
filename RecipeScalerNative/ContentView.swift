import SwiftUI

struct ContentView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var syncService: YjsSyncService
    @State private var showSplash = true
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("ui-testing")

    /// Debug: auto-authenticate on simulator
    private let debugUserId = "cfcd839f-56f2-4411-9632-7795b75f96d1"

    init() {
        let database = try! YrsDatabase()
        let store = YDocStore(dbQueue: database.dbQueue)
        _syncService = StateObject(wrappedValue: YjsSyncService(store: store))
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
        #if !targetEnvironment(simulator)
        .onChange(of: authService.isAuthenticated) { _, authenticated in
            if !authenticated {
                syncService.stop()
            }
        }
        #endif
    }

    @ViewBuilder
    private func appShell(syncService: YjsSyncService) -> some View {
        AppShellView()
            .environmentObject(syncService)
            .task(id: effectiveUserId) {
                #if DEBUG
                AgentSyncDebugLog.write(
                    hypothesisId: "boot",
                    location: "ContentView.swift:appShell",
                    message: "app_shell_start",
                    data: ["userId": effectiveUserId ?? "nil"]
                )
                #endif
                if let userId = effectiveUserId {
                    await syncService.start(userId: userId)
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
