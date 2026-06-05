//
//  RecipeScalerNativeApp.swift
//  RecipeScalerNative
//
//

import SwiftUI
import SwiftData
import UIKit
#if DEBUG
import Agentation
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            await PushRegistrationService.shared.register(apnsToken: token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] Registration failed: \(error.localizedDescription)")
    }
}

@main
struct RecipeScalerNativeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Install bundle swizzle + apply stored language preference before any
        // SwiftUI view body evaluates `String(localized:)` / `LocalizedStringKey`.
        AppLanguagePreference.bootstrap()
        TimerManager.registerBackgroundTasksIfNeeded()
        AppChromeAppearance.configure()
        #if DEBUG
        Agentation.shared.install()
        #endif
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            Ingredient.self,
            RecipeTimer.self,
            ApiCacheEntry.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }

}
