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
                RecipeListView()
                    .environmentObject(syncService)
                    .task(id: effectiveUserId) {
                        if let userId = effectiveUserId {
                            await syncService.start(userId: userId)
                        }
                    }
            } else {
                AuthView()
            }
        }
        .task {
            if isUITesting {
                showSplash = false
            } else {
                try? await Task.sleep(nanoseconds: 500_000_000)
                showSplash = false
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.rootContent)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
